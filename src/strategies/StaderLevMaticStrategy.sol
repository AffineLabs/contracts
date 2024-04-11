// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IFlashLoanReceiver as IAAVEFlashLoanReceiver} from
    "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import {WETH as IWMATIC} from "solmate/src/tokens/WETH.sol";

import {AffineVault, Strategy} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {IBalancerVault, IFlashLoanRecipient, IBalancerQueries} from "src/interfaces/balancer.sol";
import {SlippageUtils} from "src/libs/audited/SlippageUtils.sol";
import {IChildPool} from "src/interfaces/stader/IChildPool.sol";
import {ReentrancyGuard} from "src/utils/ReentrancyGuard.sol";

contract StaderLevMaticStrategy is AccessStrategy, ReentrancyGuard, IFlashLoanRecipient, IAAVEFlashLoanReceiver {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWMATIC;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(AffineVault _vault, address[] memory strategists) AccessStrategy(_vault, strategists) {
        /* Deposit flow */
        // Trade wEth for wstETH (or equivalent, e.g. cbETH)
        WMATIC.safeApprove(address(BALANCER), type(uint256).max);
        WMATIC.safeApprove(address(AAVE), type(uint256).max);

        // Deposit wstETH in AAVE
        MATICX.safeApprove(address(BALANCER), type(uint256).max);
        MATICX.safeApprove(address(AAVE), type(uint256).max);

        /* Get/Set aave information */

        aToken = ERC20(AAVE.getReserveData(address(MATICX)).aTokenAddress);
        debtToken = ERC20(AAVE.getReserveData(address(WMATIC)).variableDebtTokenAddress);

        // This enables E-mode. It allows us to borrow at 90% of the value of our collateral.
        AAVE.setUserEMode(2); // 2 for matic correlation
    }

    /*//////////////////////////////////////////////////////////////
                              FLASH LOANS
    //////////////////////////////////////////////////////////////*/

    /// @notice The balancer vault. We'll flashloan wETH from here.
    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    // @notice handle query vault for out amount
    IBalancerQueries public constant BALANCER_QUERY = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    bytes32 public constant POOL_ID = 0xcd78a20c597e367a4e478a2411ceb790604d7c8f000000000000000000000c22;

    /// @notice The different reasons for a flashloan.
    enum LoanType {
        invest,
        divest,
        upgrade,
        incLev,
        decLev
    }

    /// @notice Flash Loan source
    enum FLOrigin {
        balancer,
        aave
    }

    error onlyBalancerVault();
    error onlyAAVEVault();

    /// @notice Callback called by balancer vault after flash loan is initiated.
    function _flashLoan(uint256 amount, LoanType loan, address recipient, FLOrigin origin) internal nonReentrant {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        if (origin == FLOrigin.balancer) {
            ERC20[] memory tokens = new ERC20[](1);
            tokens[0] = WMATIC;
            BALANCER.flashLoan({
                recipient: IFlashLoanRecipient(address(this)),
                tokens: tokens,
                amounts: amounts,
                userData: abi.encode(loan, recipient)
            });
        } else {
            address[] memory tokens = new address[](1);
            tokens[0] = address(WMATIC);

            uint256[] memory modes = new uint256[](1);
            modes[0] = 0;

            AAVE.flashLoan({
                receiverAddress: address(this),
                assets: tokens,
                amounts: amounts,
                interestRateModes: modes,
                onBehalfOf: address(this),
                params: abi.encode(loan, recipient),
                referralCode: 0
            });
        }
    }

    function _manageFlashLoan(uint256 amount, uint256 fee, LoanType loan, address newStrategy) internal {
        if (loan == LoanType.divest) {
            _endPosition(amount);
        } else if (loan == LoanType.invest) {
            _addToPosition(amount);
        } else if (loan == LoanType.upgrade) {
            _payDebtAndTransferCollateral(StaderLevMaticStrategy(payable(newStrategy)));
        } else {
            /// @dev separate out the fees
            _rebalancePosition(amount - fee, loan);
        }
    }

    function receiveFlashLoan(
        ERC20[] memory, /* tokens */
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        if (msg.sender != address(BALANCER)) revert onlyBalancerVault();
        require(_reentrancyGuardEntered(), "SLMS: Invalid FL origin");
        // There will only be a new strategy in the case of an upgrade.
        (LoanType loan, address newStrategy) = abi.decode(userData, (LoanType, address));

        _manageFlashLoan(amounts[0], 0, loan, newStrategy);
        // Payback wETH loan
        WMATIC.safeTransfer(address(BALANCER), amounts[0]);
    }

    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
        return AAVE.ADDRESSES_PROVIDER();
    }

    function POOL() external pure override returns (IPool) {
        return AAVE;
    }

    function executeOperation(
        address[] calldata, /* assets */
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(AAVE)) revert onlyAAVEVault();
        require(_reentrancyGuardEntered() && initiator == address(this), "SLMS: Invalid FL origin");

        (LoanType loan, address newStrategy) = abi.decode(params, (LoanType, address));
        _manageFlashLoan(amounts[0], premiums[0], loan, newStrategy);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Add to leveraged position  upon investment from vault.
    function _afterInvest(uint256 amount) internal virtual override {
        _flashLoan(amount.mulDivDown(MAX_BPS, MAX_BPS - borrowBps), LoanType.invest, address(0), FLOrigin.balancer);
    }

    function _getSwapAmount(address from, address to, uint256 fromAmount)
        internal
        returns (
            uint256 toAmount,
            IBalancerVault.SingleSwap memory swapInfo,
            IBalancerVault.FundManagement memory fmInfo
        )
    {
        swapInfo = IBalancerVault.SingleSwap({
            poolId: POOL_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: from,
            assetOut: to,
            amount: fromAmount,
            userData: ""
        });

        fmInfo = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        toAmount = BALANCER_QUERY.querySwap(swapInfo, fmInfo);
    }

    /// @dev Add to leveraged position. Trade ETH to wstETH, deposit in AAVE, and borrow to repay balancer loan.
    function _addToPosition(uint256 loanAmount) internal {
        WMATIC.withdraw(loanAmount);
        STADER.swapMaticForMaticXViaInstantPool{value: loanAmount}();
        // Deposit wstETH in AAVE
        AAVE.supply(address(MATICX), MATICX.balanceOf(address(this)), address(this), 0);

        // Borrow 90% of wstETH value in ETH using e-mode
        uint256 toBorrow = loanAmount - WMATIC.balanceOf(address(this));
        AAVE.borrow(address(WMATIC), toBorrow, 2, 0, address(this));
    }

    /// @dev We need this to receive ETH when calling wETH.withdraw()
    receive() external payable {}

    /// @dev Unlock wstETH collateral via flashloan, then repay balancer loan with unlocked collateral.
    function _divest(uint256 amount) internal virtual override returns (uint256) {
        uint256 flashLoanAmount = _getDivestFlashLoanAmounts(amount);

        uint256 origAssets = WMATIC.balanceOf(address(this));
        _flashLoan(flashLoanAmount, LoanType.divest, address(0), FLOrigin.aave);
        // The loan has been paid, any other unlocked collateral belongs to user
        uint256 unlockedAssets = WMATIC.balanceOf(address(this)) - origAssets;
        WMATIC.safeTransfer(address(vault), Math.min(unlockedAssets, amount));
        return unlockedAssets;
    }

    /// @dev Calculate the amount of ETH needed to flashloan to divest `wethToDivest` wETH.
    function _getDivestFlashLoanAmounts(uint256 amountToDivest) internal view returns (uint256 flashLoanAmount) {
        // Proportion of tvl == proportion of debt to pay back
        uint256 tvl = totalLockedValue();
        flashLoanAmount = _debt();
        if (tvl > amountToDivest) {
            flashLoanAmount = _debt().mulDivDown(amountToDivest, tvl);
        }
    }

    function _swapMaticXToMatic(uint256 amount) internal returns (uint256) {
        IBalancerVault.SingleSwap memory swapInfo;
        IBalancerVault.FundManagement memory fmInfo;

        uint256 outAmount;

        (outAmount, swapInfo, fmInfo) = _getSwapAmount(address(MATICX), address(WMATIC), amount);

        uint256 minAmount = outAmount.slippageDown(slippageBps);

        return BALANCER.swap(swapInfo, fmInfo, minAmount, block.timestamp);
    }

    function _endPosition(uint256 loanAmount) internal {
        // Proportion of collateral to unlock is same as proportion of debt to pay back (ethBorrowed / debt)
        // We need to calculate this number before paying back debt, since the fraction will change.
        uint256 stMaticToRedeem = aToken.balanceOf(address(this)).mulDivDown(loanAmount, _debt());

        // Pay debt in aave
        AAVE.repay(address(WMATIC), loanAmount, 2, address(this));

        // Withdraw same proportion of collateral from aave
        AAVE.withdraw(address(MATICX), stMaticToRedeem, address(this));
        _swapMaticXToMatic(MATICX.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                              REBALANCING
    //////////////////////////////////////////////////////////////*/

    function rebalance() external virtual onlyRole(STRATEGIST_ROLE) {
        uint256 debt = _debt();
        uint256 collateral = _collateral();
        uint256 expectedDebt = collateral.mulDivDown(borrowBps, MAX_BPS);

        if (expectedDebt > debt) {
            // inc lev
            _flashLoan(
                (expectedDebt - debt).mulDivDown(MAX_BPS, MAX_BPS - borrowBps),
                LoanType.incLev,
                address(0),
                FLOrigin.balancer
            );
        } else {
            _flashLoan(
                (debt - expectedDebt).mulDivDown(MAX_BPS, MAX_BPS - borrowBps),
                LoanType.decLev,
                address(0),
                FLOrigin.aave
            );
        }
    }

    function _rebalancePosition(uint256 loanAmount, LoanType loan) internal {
        if (loan == LoanType.incLev) {
            _addToPosition(loanAmount);
        } else {
            // repay
            AAVE.repay(address(WMATIC), loanAmount, 2, address(this));
            // get wsteth amount from eth
            (uint256 stMaticAmount,,) = _getSwapAmount(address(WMATIC), address(MATICX), loanAmount);
            uint256 stMaticToRedeem = stMaticAmount.slippageUp(slippageBps);
            // withdraw from aave
            AAVE.withdraw(address(MATICX), stMaticToRedeem, address(this));

            _swapMaticXToMatic(MATICX.balanceOf(address(this)));
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VALUATION
    //////////////////////////////////////////////////////////////*/

    function _debt() internal view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    function _collateral() internal view returns (uint256) {
        (uint256 amount,,) = STADER.convertMaticXToMatic(aToken.balanceOf(address(this)));
        return amount;
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

    /// @notice The wrapped matic address.
    IWMATIC public constant WMATIC = IWMATIC(payable(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270));

    /// @notice Lev Assets Liquid Staking Matic MATICX
    ERC20 public constant MATICX = ERC20(0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6); // polygon
    /// @notice stader proxy child pool
    IChildPool public constant STADER = IChildPool(0xfd225C9e6601C9d38d8F98d8731BF59eFcF8C0E3); // polygon

    /*//////////////////////////////////////////////////////////////
                                 TRADES
    //////////////////////////////////////////////////////////////*/

    /// @notice The acceptable slippage on trades.
    uint256 public slippageBps = 10;
    /// @dev max slippage on curve is around 10pbs for 10 eth

    /// @notice Set slippageBps.
    function setSlippageBps(uint256 _slippageBps) external onlyRole(STRATEGIST_ROLE) {
        slippageBps = _slippageBps;
    }
    // /*//////////////////////////////////////////////////////////////
    //                               AAVE
    // //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS = 10_000;
    /// @notice amount to borrow after lending in the platform
    uint256 public borrowBps = 9000; // default 90% for aave e-mode

    /// @notice Set the borrowing factor.
    /// @param _borrowBps The new borrow factor.
    function setBorrowBps(uint256 _borrowBps) external onlyRole(STRATEGIST_ROLE) {
        borrowBps = _borrowBps;
    }

    /// @notice The Aave lending pool.
    IPool public constant AAVE = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // polygon address

    /// @notice The debtToken for wETH.
    ERC20 public immutable debtToken;

    /// @notice THe aToken for wstETH.
    ERC20 public immutable aToken;

    // /*//////////////////////////////////////////////////////////////
    //                             UPGRADES
    // //////////////////////////////////////////////////////////////*/

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
    function upgradeTo(StaderLevMaticStrategy newStrategy) external onlyGovernance {
        _checkIfStrategy(newStrategy);
        _flashLoan(debtToken.balanceOf(address(this)), LoanType.upgrade, address(newStrategy), FLOrigin.balancer);
    }

    /// @dev Pay debt and transfer collateral to new strategy.
    function _payDebtAndTransferCollateral(StaderLevMaticStrategy newStrategy) internal {
        _checkIfStrategy(newStrategy);
        // Pay debt in aave.
        uint256 debt = debtToken.balanceOf(address(this));
        AAVE.repay(address(WMATIC), debt, 2, address(this));

        // Transfer collateral (aTokens) to new Strategy.
        aToken.safeTransfer(address(newStrategy), aToken.balanceOf(address(this)));

        // Make the new strategy borrow exactly the same amount as this strategy originally had in debt.
        newStrategy.createAaveDebt(debt);
    }

    /// @notice Callback called by an old strategy that is moving its assets to this strategy. See `upgradeTo`.
    function createAaveDebt(uint256 wethAmount) external {
        _checkIfStrategy(Strategy(msg.sender));
        AAVE.borrow(address(WMATIC), wethAmount, 2, 0, address(this));

        // Transfer weth to calling strategy (old LidoLevL2) so that it can pay its flashloan.
        WMATIC.safeTransfer(msg.sender, wethAmount);
    }

    /// @dev Check if the address is a valid strategy.
    function _checkIfStrategy(Strategy strat) internal view {
        (bool isActive,,) = vault.strategies(strat);
        if (!isActive) revert NotAStrategy();
    }
}
