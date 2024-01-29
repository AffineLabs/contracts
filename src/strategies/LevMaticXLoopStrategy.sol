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
import {SlippageUtils} from "src/libs/SlippageUtils.sol";
import {IChildPool} from "src/interfaces/stader/IChildPool.sol";

contract LevMaticXLoopStrategy is AccessStrategy, IFlashLoanRecipient {
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

    /*//////////////////////////////////////////////////////////////
                         INVESTMENT/DIVESTMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev investment cycle
    uint256 public iCycle = 10;

    function setInvestmentCycle(uint256 _iCycle) external {
        require(_iCycle > 0, "LM6X: invalid loop.");
        iCycle = _iCycle;
    }

    /// @dev Add to leveraged position  upon investment from vault.
    function _afterInvest(uint256 amount) internal override {
        for (uint256 i = 0; i < iCycle; i++) {
            WMATIC.withdraw(amount);
            STADER.swapMaticForMaticXViaInstantPool{value: amount}();
            // Deposit wstETH in AAVE
            AAVE.supply(address(MATICX), MATICX.balanceOf(address(this)), address(this), 0);

            // Borrow 90% of wstETH value in ETH using e-mode
            uint256 toBorrow = amount.mulDivDown(borrowBps, MAX_BPS);
            AAVE.borrow(address(WMATIC), toBorrow, 2, 0, address(this));
            amount = toBorrow;
        }
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

    function _swapMaticToMaticX(uint256 amount) public returns (uint256) {
        IBalancerVault.SingleSwap memory swapInfo;
        IBalancerVault.FundManagement memory fmInfo;

        uint256 outAmount;

        (outAmount, swapInfo, fmInfo) = _getSwapAmount(address(WMATIC), address(MATICX), amount);

        uint256 minAmount = outAmount.slippageDown(5000);
        uint256 ret = BALANCER.swap(swapInfo, fmInfo, minAmount, block.timestamp);
        return ret;
    }

    /// @dev We need this to receive ETH when calling wETH.withdraw()
    receive() external payable {}

    /// @dev Unlock wstETH collateral via flashloan, then repay balancer loan with unlocked collateral.
    function _divest(uint256 amount) internal override returns (uint256) {
        uint256 tvl = totalLockedValue();
        uint256 repayAmount =
            amount < tvl ? WMATIC.balanceOf(address(this)).mulDivDown(amount, tvl) : WMATIC.balanceOf(address(this));

        uint256 postRes = WMATIC.balanceOf(address(this)) - repayAmount;

        AAVE.repay(address(WMATIC), repayAmount, 2, address(this));
        uint256 stMaticToRedeem;
        uint256 amountReceived;
        for (uint256 i = 1; i <= iCycle; i++) {
            uint256 exCollateral = _collateral() - _debt().mulDivUp(MAX_BPS, borrowBps);
            (stMaticToRedeem,,) = STADER.convertMaticToMaticX(exCollateral);
            AAVE.withdraw(address(MATICX), stMaticToRedeem, address(this));
            amountReceived = _swapMaticXToMatic(MATICX.balanceOf(address(this)));
            if (i < iCycle) {
                AAVE.repay(address(WMATIC), amountReceived, 2, address(this));
            }
        }
        uint256 unlockedAssets = WMATIC.balanceOf(address(this)) - postRes;
        WMATIC.safeTransfer(address(vault), unlockedAssets);
        return unlockedAssets;
    }

    function _swapMaticXToMatic(uint256 amount) internal returns (uint256) {
        IBalancerVault.SingleSwap memory swapInfo;
        IBalancerVault.FundManagement memory fmInfo;

        uint256 outAmount;

        (outAmount, swapInfo, fmInfo) = _getSwapAmount(address(MATICX), address(WMATIC), amount);

        uint256 minAmount = outAmount.slippageDown(slippageBps);

        return BALANCER.swap(swapInfo, fmInfo, minAmount, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              REBALANCING
    //////////////////////////////////////////////////////////////*/

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
        return _collateral() - _debt() + WMATIC.balanceOf(address(this));
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
    error onlyBalancerVault();

    /**
     * @notice Upgrade to a new strategy.
     * @dev Transfer all of this strategy's assets to a new one, without any losses.
     * 1. This strategy flashloans it's current aave debt from balancer, pays it, and transfers it's collateral to the
     * new strategy.
     * 2. This strategy calls `createAaveDebt` on the new strategy, such that new strategy has the same aave debt as
     * this strategy did before the upgrade.
     * 3. The new strategy transfers the wETH it borrowed back to this strategy, so that the flashloan can be repaid.
     */
    function receiveFlashLoan(
        ERC20[] memory, /* tokens */
        uint256[] memory amounts,
        uint256[] memory, /* feeAmounts */
        bytes memory userData
    ) external override {
        if (msg.sender != address(BALANCER)) revert onlyBalancerVault();

        // There will only be a new strategy in the case of an upgrade.
        (address newStrategy) = abi.decode(userData, (address));
        _payDebtAndTransferCollateral(LevMaticXLoopStrategy(payable(newStrategy)));
        // Payback wETH loan
        WMATIC.safeTransfer(address(BALANCER), amounts[0]);
    }

    function upgradeTo(LevMaticXLoopStrategy newStrategy) external onlyGovernance {
        _checkIfStrategy(newStrategy);

        // transfer res assets to new strategy
        WMATIC.safeTransfer(address(newStrategy), WMATIC.balanceOf(address(this)));

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WMATIC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtToken.balanceOf(address(this));

        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(this)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(address(newStrategy))
        });
    }

    /// @dev Pay debt and transfer collateral to new strategy.
    function _payDebtAndTransferCollateral(LevMaticXLoopStrategy newStrategy) internal {
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
