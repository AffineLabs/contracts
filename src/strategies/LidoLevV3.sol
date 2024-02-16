// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH as IWETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {ReentrancyGuard} from "src/utils/ReentrancyGuard.sol";
import {AffineVault, Strategy} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IBalancerVault, IFlashLoanRecipient} from "src/interfaces/balancer.sol";
import {IWSTETH} from "src/interfaces/lido/IWSTETH.sol";
import {ICurvePool} from "src/interfaces/curve/ICurvePool.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {SlippageUtils} from "src/libs/audited/SlippageUtils.sol";

contract LidoLevV3 is AccessStrategy, ReentrancyGuard, IFlashLoanRecipient {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWETH;
    using SafeTransferLib for IWSTETH;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(AffineVault _vault, address[] memory strategists) AccessStrategy(_vault, strategists) {
        /* Deposit flow */
        // Trade wEth for wstETH (or equivalent, e.g. cbETH)
        WETH.safeApprove(address(CURVE), type(uint256).max);

        // Deposit wstETH in AAVE
        WSTETH.safeApprove(address(AAVE), type(uint256).max);

        /* Withdrawal flow */

        // Pay wETH debt in aave
        WETH.safeApprove(address(AAVE), type(uint256).max);

        STETH.approve(address(CURVE), type(uint256).max);

        /* Get/Set aave information */

        aToken = ERC20(AAVE.getReserveData(address(WSTETH)).aTokenAddress);
        debtToken = ERC20(AAVE.getReserveData(address(WETH)).variableDebtTokenAddress);

        // This enables E-mode. It allows us to borrow at 90% of the value of our collateral.
        AAVE.setUserEMode(1);
    }

    /*//////////////////////////////////////////////////////////////
                              FLASH LOANS
    //////////////////////////////////////////////////////////////*/

    /// @notice The balancer vault. We'll flashloan wETH from here.
    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /// @notice The different reasons for a flashloan.
    enum LoanType {
        invest,
        divest,
        upgrade,
        incLev,
        decLev
    }

    error onlyBalancerVault();

    /// @notice Callback called by balancer vault after flashloan is initiated.
    function _flashLoan(uint256 amount, LoanType loan, address recipient) internal nonReentrant {
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(loan, recipient)
        });
    }

    function receiveFlashLoan(
        ERC20[] memory, /* tokens */
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        if (msg.sender != address(BALANCER)) revert onlyBalancerVault();
        require(_reentrancyGuardEntered(), "LLV3: Invalid FL origin");

        uint256 ethBorrowed = amounts[0];

        // There will only be a new strategy in the case of an upgrade.
        (LoanType loan, address newStrategy) = abi.decode(userData, (LoanType, address));

        if (loan == LoanType.divest) {
            _endPosition(ethBorrowed);
        } else if (loan == LoanType.invest) {
            _addToPosition(ethBorrowed);
        } else if (loan == LoanType.upgrade) {
            _payDebtAndTransferCollateral(LidoLevV3(payable(newStrategy)));
        } else {
            _rebalancePosition(ethBorrowed, loan);
        }

        // Payback wETH loan
        WETH.safeTransfer(address(BALANCER), ethBorrowed);
    }

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Add to leveraged position  upon investment from vault.
    function _afterInvest(uint256 amount) internal override {
        _flashLoan(amount.mulDivDown(MAX_BPS, MAX_BPS - borrowBps), LoanType.invest, address(0));
    }

    /// @dev Add to leveraged position. Trade ETH to wstETH, deposit in AAVE, and borrow to repay balancer loan.
    function _addToPosition(uint256 ethBorrowed) internal {
        // withdraw eth from weth
        WETH.withdraw(ethBorrowed);

        (bool success,) = payable(address(WSTETH)).call{value: ethBorrowed}("");

        require(success, "LLV3: WstEth failed");
        // Deposit wstETH in AAVE
        AAVE.deposit(address(WSTETH), WSTETH.balanceOf(address(this)), address(this), 0);

        // Borrow 90% of wstETH value in ETH using e-mode
        uint256 ethToBorrow = ethBorrowed - WETH.balanceOf(address(this));
        AAVE.borrow(address(WETH), ethToBorrow, 2, 0, address(this));
    }

    /// @dev We need this to receive ETH when calling wETH.withdraw()
    receive() external payable {}

    /// @dev Unlock wstETH collateral via flashloan, then repay balancer loan with unlocked collateral.
    function _divest(uint256 amount) internal override returns (uint256) {
        uint256 ethNeeded = _getDivestFlashLoanAmounts(amount);

        uint256 origAssets = WETH.balanceOf(address(this));

        _flashLoan(ethNeeded, LoanType.divest, address(0));
        // The loan has been paid, any other unlocked collateral belongs to user
        uint256 unlockedWeth = WETH.balanceOf(address(this)) - origAssets;
        WETH.safeTransfer(address(vault), Math.min(unlockedWeth, amount));
        return unlockedWeth;
    }

    /// @dev Calculate the amount of ETH needed to flashloan to divest `wethToDivest` wETH.
    function _getDivestFlashLoanAmounts(uint256 wethToDivest) internal view returns (uint256 ethNeeded) {
        // Proportion of tvl == proportion of debt to pay back
        uint256 tvl = totalLockedValue();
        ethNeeded = _debt();
        if (tvl > wethToDivest) {
            ethNeeded = _debt().mulDivDown(wethToDivest, tvl);
        }
    }

    function _convertStEthToWeth(uint256 amount, uint256 minAmount) internal {
        uint256 ethReceived = CURVE.exchange({x: int128(1), y: int128(0), dx: amount, min_dy: minAmount});
        // convert eth to weth
        WETH.deposit{value: ethReceived}();
    }

    function _endPosition(uint256 ethBorrowed) internal {
        // Proportion of collateral to unlock is same as proportion of debt to pay back (ethBorrowed / debt)
        // We need to calculate this number before paying back debt, since the fraction will change.
        uint256 wstEthToRedeem = aToken.balanceOf(address(this)).mulDivDown(ethBorrowed, _debt());

        // Pay debt in aave
        AAVE.repay(address(WETH), ethBorrowed, 2, address(this));

        // Withdraw same proportion of collateral from aave
        AAVE.withdraw(address(WSTETH), wstEthToRedeem, address(this));

        // withdraw eth from wsteth
        WSTETH.unwrap(WSTETH.balanceOf(address(this)));

        // convert stEth to eth
        _convertStEthToWeth(STETH.balanceOf(address(this)), STETH.balanceOf(address(this)).slippageDown(slippageBps));
    }

    /*//////////////////////////////////////////////////////////////
                              REBALANCING
    //////////////////////////////////////////////////////////////*/

    function rebalance() external onlyRole(STRATEGIST_ROLE) {
        uint256 debt = _debt();
        uint256 collateral = _collateral();
        uint256 expectedDebt = collateral.mulDivDown(borrowBps, MAX_BPS);

        if (expectedDebt > debt) {
            // inc lev
            _flashLoan((expectedDebt - debt).mulDivDown(MAX_BPS, MAX_BPS - borrowBps), LoanType.incLev, address(0));
        } else {
            _flashLoan((debt - expectedDebt).mulDivDown(MAX_BPS, MAX_BPS - borrowBps), LoanType.decLev, address(0));
        }
    }

    function _rebalancePosition(uint256 ethBorrowed, LoanType loan) internal {
        if (loan == LoanType.incLev) {
            _addToPosition(ethBorrowed);
        } else {
            // repay
            AAVE.repay(address(WETH), ethBorrowed, 2, address(this));
            // get wsteth amount from eth
            uint256 wstEthToRedeem = WSTETH.getWstETHByStETH(ethBorrowed).slippageUp(slippageBps);
            // withdraw from aave
            AAVE.withdraw(address(WSTETH), wstEthToRedeem, address(this));
            // unwrap wsteth
            WSTETH.unwrap(WSTETH.balanceOf(address(this)));
            // conv steth to weth
            _convertStEthToWeth(STETH.balanceOf(address(this)), ethBorrowed);
            if (WETH.balanceOf(address(this)) > ethBorrowed) {
                AAVE.repay(address(WETH), WETH.balanceOf(address(this)) - ethBorrowed, 2, address(this));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VALUATION
    //////////////////////////////////////////////////////////////*/

    function _debt() internal view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    function _collateral() internal view returns (uint256) {
        return WSTETH.getStETHByWstETH(aToken.balanceOf(address(this)));
    }

    /// @notice The tvl function.
    function totalLockedValue() public view override returns (uint256) {
        return _collateral() - _debt();
    }

    function getLTVRatio() public view returns (uint256) {
        return _debt().mulDivDown(MAX_BPS, _collateral());
    }

    /*//////////////////////////////////////////////////////////////
                                  STAKED ETHER
    //////////////////////////////////////////////////////////////*/

    /// @notice The wETH address.
    IWETH public constant WETH = IWETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    /// @notice The wstETH address (actually cbETH on Base).
    IWSTETH public constant WSTETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // eth
    ERC20 public constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84); // eth

    /*//////////////////////////////////////////////////////////////
                                 TRADES
    //////////////////////////////////////////////////////////////*/

    /// @notice The curve pool used for stETH <=>  eth.
    ICurvePool public constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022); // eth address

    /// @notice The acceptable slippage on trades.
    uint256 public slippageBps = 10;
    /// @dev max slippage on curve is around 10pbs for 10 eth

    /// @notice Set slippageBps.
    function setSlippageBps(uint256 _slippageBps) external onlyRole(STRATEGIST_ROLE) {
        slippageBps = _slippageBps;
    }
    /*//////////////////////////////////////////////////////////////
                                  AAVE
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS = 10_000;
    /// @notice amount to borrow after lending in the platform
    uint256 public borrowBps = 8999; // default 90% for aave e-mode

    /// @notice Set the borrowing factor.
    /// @param _borrowBps The new borrow factor.
    function setBorrowBps(uint256 _borrowBps) external onlyRole(STRATEGIST_ROLE) {
        borrowBps = _borrowBps;
    }

    /// @notice The Aave lending pool.
    IPool public constant AAVE = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // eth address

    /// @notice The debtToken for wETH.
    ERC20 public immutable debtToken;

    /// @notice THe aToken for wstETH.
    ERC20 public immutable aToken;

    /*//////////////////////////////////////////////////////////////
                                UPGRADES
    //////////////////////////////////////////////////////////////*/

    error NotAStrategy();

    /**
     * @notice Upgrade to a new strategy.
     * @dev Transfer all of this strategy's assets to a new one, without any losses.
     * 1. This strategy flashloans it's current aave debt from balancer, pays it, and transfers it's collateral to the
     * new strategy.
     * 2. This strategy calls `createAaveDebt` on the new strategy, such that new strategy has the same aave debt as
     * this strategy did before the upgrade.
     * 3. The new strategy transfers the wETH it borrowed back to this strategy, so that the flashloan can be repaid.
     */
    function upgradeTo(LidoLevV3 newStrategy) external onlyGovernance {
        _checkIfStrategy(newStrategy);
        _flashLoan(debtToken.balanceOf(address(this)), LoanType.upgrade, address(newStrategy));
    }

    /// @dev Pay debt and transfer collateral to new strategy.
    function _payDebtAndTransferCollateral(LidoLevV3 newStrategy) internal {
        _checkIfStrategy(newStrategy);
        // Pay debt in aave.
        uint256 debt = debtToken.balanceOf(address(this));
        AAVE.repay(address(WETH), debt, 2, address(this));

        // Transfer collateral (aTokens) to new Strategy.
        aToken.safeTransfer(address(newStrategy), aToken.balanceOf(address(this)));

        // Make the new strategy borrow exactly the same amount as this strategy originally had in debt.
        newStrategy.createAaveDebt(debt);
    }

    /// @notice Callback called by an old strategy that is moving its assets to this strategy. See `upgradeTo`.
    function createAaveDebt(uint256 wethAmount) external {
        _checkIfStrategy(Strategy(msg.sender));
        AAVE.borrow(address(WETH), wethAmount, 2, 0, address(this));

        // Transfer weth to calling strategy (old LidoLevL2) so that it can pay its flashloan.
        WETH.safeTransfer(msg.sender, wethAmount);
    }

    /// @dev Check if the address is a valid strategy.
    function _checkIfStrategy(Strategy strat) internal view {
        (bool isActive,,) = vault.strategies(strat);
        if (!isActive) revert NotAStrategy();
    }
}
