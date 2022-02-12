// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

import { BaseStrategy as Strategy } from "./BaseStrategy.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";
import { IStaging } from "./interfaces/IStaging.sol";
import { Staging } from "./Staging.sol";
import { ICreate2Deployer } from "./interfaces/ICreate2Deployer.sol";

abstract contract BaseVault is Initializable, AccessControl {
    using SafeTransferLib for ERC20;

    // The token that the vault takes in and gives to strategies, e.g. USDC
    ERC20 public token;

    address public governance;
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }

    // Wormhole contract for sending/receiving messages
    IWormhole public wormhole;
    address public staging;

    /** Authentication
     **************************************************************************/

    bytes32 public constant bankerRole = keccak256("BANKER");
    bytes32 public constant stackOperatorRole = keccak256("STACK_OPERATOR");

    /** Withdrawal Stack
     **************************************************************************/

    uint8 public constant MAX_STRATEGIES = 20;

    /// @notice An ordered array of strategies representing the withdrawal stack.
    /// @dev The stack is processed in descending order, meaning the last index will be withdrawn from first.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are filtered out when encountered at
    /// withdrawal time, not validated upfront, meaning the stack may not reflect the "true" set used for withdrawals.
    Strategy[] public withdrawalStack;

    /// @notice Gets the full withdrawal stack.
    /// @return An ordered array of strategies representing the withdrawal stack.
    /// @dev This is provided because Solidity converts public arrays into index getters,
    /// but we need a way to allow external contracts and users to access the whole array.
    function getWithdrawalStack() external view returns (Strategy[] memory) {
        return withdrawalStack;
    }

    /// @notice Pushes a single strategy to front of the withdrawal stack.
    /// @param strategy The strategy to be inserted at the front of the withdrawal stack.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function pushToWithdrawalStack(Strategy strategy) external onlyRole(stackOperatorRole) {
        _pushToWithdrawalStack(strategy);
    }

    /// @dev This is to maintain the old logic where a strategy gets added to the withdrawal stack
    /// right when it is added
    function _pushToWithdrawalStack(Strategy strategy) internal {
        // Ensure pushing the strategy will not cause the stack exceed its limit.
        require(withdrawalStack.length < MAX_STRATEGIES, "STACK_FULL");

        // Push the strategy to the front of the stack.
        withdrawalStack.push(strategy);

        emit WithdrawalStackPushed(msg.sender, strategy);
    }

    /// @notice Removes the strategy at the tip of the withdrawal stack.
    /// @dev Be careful, another authorized user could push a different strategy
    /// than expected to the stack while a popFromWithdrawalStack transaction is pending.
    function popFromWithdrawalStack() external onlyRole(stackOperatorRole) {
        // Get the (soon to be) popped strategy.
        Strategy poppedStrategy = withdrawalStack[withdrawalStack.length - 1];

        // Pop the first strategy in the stack.
        withdrawalStack.pop();

        emit WithdrawalStackPopped(msg.sender, poppedStrategy);
    }

    /// @notice Sets a new withdrawal stack.
    /// @param newStack The new withdrawal stack.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalStack(Strategy[] calldata newStack) external onlyRole(stackOperatorRole) {
        // Ensure the new stack is not larger than the maximum stack size.
        require(newStack.length <= MAX_STRATEGIES, "STACK_TOO_BIG");

        // Replace the withdrawal stack.
        withdrawalStack = newStack;

        emit WithdrawalStackSet(msg.sender, newStack);
    }

    /// @notice Replaces an index in the withdrawal stack with another strategy.
    /// @param index The index in the stack to replace.
    /// @param replacementStrategy The strategy to override the index with.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function replaceWithdrawalStackIndex(uint256 index, Strategy replacementStrategy)
        external
        onlyRole(stackOperatorRole)
    {
        // Get the (soon to be) replaced strategy.
        Strategy replacedStrategy = withdrawalStack[index];

        // Update the index with the replacement strategy.
        withdrawalStack[index] = replacementStrategy;

        emit WithdrawalStackIndexReplaced(msg.sender, index, replacedStrategy, replacementStrategy);
    }

    /// @notice Moves the strategy at the tip of the stack to the specified index and pop the tip off the stack.
    /// @param index The index of the strategy in the withdrawal stack to replace with the tip.
    /// @dev This isn't so necessary and can probably be removed. TODO: consider removing
    function replaceWithdrawalStackIndexWithTip(uint256 index) external onlyRole(stackOperatorRole) {
        // Get the (soon to be) previous tip and strategy we will replace at the index.
        Strategy previousTipStrategy = withdrawalStack[withdrawalStack.length - 1];
        Strategy replacedStrategy = withdrawalStack[index];

        // Replace the index specified with the tip of the stack.
        withdrawalStack[index] = previousTipStrategy;

        // Remove the now duplicated tip from the array.
        withdrawalStack.pop();

        emit WithdrawalStackIndexReplacedWithTip(msg.sender, index, replacedStrategy, previousTipStrategy);
    }

    /// @notice Swaps two indexes in the withdrawal stack.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    function swapWithdrawalStackIndexes(uint256 index1, uint256 index2) external onlyRole(stackOperatorRole) {
        // Get the (soon to be) new strategies at each index.
        Strategy newStrategy2 = withdrawalStack[index1];
        Strategy newStrategy1 = withdrawalStack[index2];

        // Swap the strategies at both indexes.
        withdrawalStack[index1] = newStrategy1;
        withdrawalStack[index2] = newStrategy2;

        emit WithdrawalStackIndexesSwapped(msg.sender, index1, index2, newStrategy1, newStrategy2);
    }

    /// @notice Emitted when a strategy is pushed to the withdrawal stack.
    /// @param user The authorized user who triggered the push.
    /// @param pushedStrategy The strategy pushed to the withdrawal stack.
    event WithdrawalStackPushed(address indexed user, Strategy indexed pushedStrategy);

    /// @notice Emitted when a strategy is popped from the withdrawal stack.
    /// @param user The authorized user who triggered the pop.
    /// @param poppedStrategy The strategy popped from the withdrawal stack.
    event WithdrawalStackPopped(address indexed user, Strategy indexed poppedStrategy);

    /// @notice Emitted when the withdrawal stack is updated.
    /// @param user The authorized user who triggered the set.
    /// @param replacedWithdrawalStack The new withdrawal stack.
    event WithdrawalStackSet(address indexed user, Strategy[] replacedWithdrawalStack);

    /// @notice Emitted when an index in the withdrawal stack is replaced.
    /// @param user The authorized user who triggered the replacement.
    /// @param index The index of the replaced strategy in the withdrawal stack.
    /// @param replacedStrategy The strategy in the withdrawal stack that was replaced.
    /// @param replacementStrategy The strategy that overrode the replaced strategy at the index.
    event WithdrawalStackIndexReplaced(
        address indexed user,
        uint256 index,
        Strategy indexed replacedStrategy,
        Strategy indexed replacementStrategy
    );

    /// @notice Emitted when an index in the withdrawal stack is replaced with the tip.
    /// @param user The authorized user who triggered the replacement.
    /// @param index The index of the replaced strategy in the withdrawal stack.
    /// @param replacedStrategy The strategy in the withdrawal stack replaced by the tip.
    /// @param previousTipStrategy The previous tip of the stack that replaced the strategy.
    event WithdrawalStackIndexReplacedWithTip(
        address indexed user,
        uint256 index,
        Strategy indexed replacedStrategy,
        Strategy indexed previousTipStrategy
    );

    /// @notice Emitted when the strategies at two indexes are swapped.
    /// @param user The authorized user who triggered the swap.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    /// @param newStrategy1 The strategy (previously at index2) that replaced index1.
    /// @param newStrategy2 The strategy (previously at index1) that replaced index2.
    event WithdrawalStackIndexesSwapped(
        address indexed user,
        uint256 index1,
        uint256 index2,
        Strategy indexed newStrategy1,
        Strategy indexed newStrategy2
    );

    /** Strategies
     **************************************************************************/
    struct StrategyInfo {
        uint256 activation;
        uint256 debtRatio;
        uint256 minDebtPerHarvest;
        uint256 maxDebtPerHarvest;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }
    // All strategy information
    mapping(Strategy => StrategyInfo) public strategies;
    event StrategyAdded(
        Strategy indexed strategy,
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest
    );
    event StrategyRemoved(Strategy indexed strategy);
    event StrategyUpdateDebtRatio(Strategy indexed strategy, uint256 debtRatio);
    event StrategyReported(
        Strategy indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 debtAdded,
        uint256 debtRatio
    );

    // debtRatio is always less than MAX_BPS
    uint256 public debtRatio;
    // Total amount that the vault can get back from strategies (ignoring slippage)
    uint256 public totalDebt;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant SECS_PER_YEAR = 31_556_952;
    uint256 public lastReport;

    //// Profit
    // maximum amount of profit locked after a report from a strategy
    uint256 public maxLockedProfit;
    // Amount of time in seconds that profit takes to fully unlock see lockedProfit().
    uint256 public constant lockInterval = 60 * 60 * 3;

    // TODO: Add some events here. Actually log events as well
    event Liquidation(uint256 amountRequested, uint256 amountLiquidated);

    function init(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer
    ) public onlyInitializing {
        governance = _governance;
        token = _token;
        wormhole = _wormhole;
        lastReport = block.timestamp;

        ICreate2Deployer deployer = create2Deployer;
        bytes memory bytecode = type(Staging).creationCode;
        staging = deployer.deploy(0, bytes32("staging1"), bytecode);
        IStaging(staging).initialize(address(this), _wormhole, _token);
    }

    function vaultTVL() public view returns (uint256) {
        return token.balanceOf(address(this)) + totalDebt;
    }

    // Current locked profit amount. Profit unlocks uniformly over `lockInterval` seconds after a report
    function lockedProfit() public view returns (uint256) {
        if (block.timestamp - lastReport > lockInterval) return 0;

        uint256 unlockedProfit = (maxLockedProfit * (block.timestamp - lastReport)) / lockInterval;
        return maxLockedProfit - unlockedProfit;
    }

    // See notes for _liquidate.
    function liquidate(uint256 amount) external onlyGovernance {
        _liquidate(amount);
    }

    // Try to get `amount` out of the strategies.
    function _liquidate(uint256 amount) internal returns (uint256) {
        uint256 amountLiquidated;
        for (uint8 i = 0; i < MAX_STRATEGIES; i++) {
            Strategy strategy = withdrawalStack[i];
            if (strategy == Strategy(address(0))) break;

            uint256 balance = token.balanceOf(address(this));
            if (balance >= amount) break;

            // NOTE: Don't withdraw more than the debt so that Strategy can still
            // continue to work based on the profits it has
            uint256 amountNeeded = amount - balance;
            amountNeeded = Math.min(amountNeeded, strategies[strategy].totalDebt);

            // Force withdraw of token from strategy
            uint256 loss = Strategy(strategy).withdraw(amountNeeded);
            uint256 withdrawn = token.balanceOf(address(this)) - balance;

            // TODO: consider loss protection
            if (loss > 0) {
                _reportLoss(strategy, loss);
            }

            // update debts, amountLiquidated
            // Reduce the Strategy's debt by the amount withdrawn ("realized returns")
            // NOTE: This doesn't add to totalGain as it's not earned by "normal means"
            amountLiquidated += withdrawn;
            strategies[strategy].totalDebt -= withdrawn;
            totalDebt -= withdrawn;
        }
        emit Liquidation(amount, amountLiquidated);
        return amountLiquidated;
    }

    function addStrategy(
        Strategy strategy,
        uint256 debtRatio_,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest
    ) external onlyGovernance {
        // Check if this strategy can be activated
        require(strategy != Strategy(address(0)), "Strategy must be not be zero account");
        require(strategies[strategy].activation == 0, "Strategy must not already be active");
        require(address(Strategy(strategy).vault()) == address(this), "Strategy must use this vault");
        require(address(token) == address(Strategy(strategy).want()), "Strategy must take profits in token");

        // Check if sanity properties violate invariants
        require(debtRatio + debtRatio_ <= MAX_BPS, "Debt cannot exceed 10k bps");
        require(minDebtPerHarvest <= maxDebtPerHarvest, "minDebtPerHarvest must not exceed max");

        // Actually add strategy
        strategies[strategy] = StrategyInfo({
            activation: block.timestamp,
            debtRatio: debtRatio_,
            minDebtPerHarvest: minDebtPerHarvest,
            maxDebtPerHarvest: maxDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });
        emit StrategyAdded(strategy, debtRatio, minDebtPerHarvest, maxDebtPerHarvest);

        // The total amount of token that could be borrowed is now larger
        debtRatio += debtRatio_;

        //  Add strategy to withdrawal queue and organize
        _pushToWithdrawalStack(strategy);
    }

    function removeStrategy(Strategy strategy) external {
        // Let governance/strategy remove the strategy
        require(msg.sender == address(strategy) || msg.sender == governance, "Only goverance or the strategy can call");
        if (strategies[strategy].debtRatio == 0) return;
        debtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = 0;
        emit StrategyRemoved(strategy);
    }

    function updateStrategyDebtRatio(Strategy strategy, uint256 debtRatio_) external onlyGovernance {
        require(strategies[strategy].activation > 0, "Strategy must be active");
        debtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = debtRatio_;
        debtRatio += debtRatio_;
        require(debtRatio <= MAX_BPS, "debtRatio may not exceed MAX_BPS");
        emit StrategyUpdateDebtRatio(strategy, debtRatio_);
    }

    function updateManyStrategyDebtRatios(Strategy[] calldata strategies_, uint256[] calldata debtRatios)
        external
        onlyGovernance
    {
        for (uint256 i = 0; i < strategies_.length; i++) {
            Strategy strategy = strategies_[i];
            uint256 newDebtRatio = debtRatios[i];
            require(strategies[strategy].activation > 0, "Strategy must be active");
            debtRatio = debtRatio - strategies[strategy].debtRatio + newDebtRatio;
            strategies[strategy].debtRatio = newDebtRatio;
        }
        require(debtRatio <= MAX_BPS, "debtRatio may not exceed MAX_BPS");
        // TODO: emit event here
    }

    // This function will be called by a strategy in order to update totalDebt;
    function report(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external returns (uint256) {
        require(strategies[Strategy(msg.sender)].activation > 0, "Strategy must be active");
        // TODO: consider health check
        Strategy strategy = Strategy(msg.sender);

        // Strategy must be able to pay (gain + debtPayment) of token
        require(token.balanceOf(address(strategy)) >= gain + debtPayment);

        if (loss > 0) _reportLoss(strategy, loss);

        strategies[strategy].totalGain += gain;
        maxLockedProfit = lockedProfit() + gain;

        // Compute the line of credit the Vault is able to offer the Strategy (if any)
        uint256 credit = creditAvailable(strategy);

        // # Amount that strategy has exceeded its debt limit
        uint256 debt = debtOutstanding(strategy);
        debtPayment = debtPayment < debt ? debtPayment : debt;

        // Update the actual debt based on the full credit we are extending to the Strategy
        // or the amount we are taking from the strategy
        // NOTE: At least one of `credit` or `debt` is always 0 (both can be 0)
        if (debtPayment > 0) {
            strategies[strategy].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }
        if (credit > 0) {
            strategies[strategy].totalDebt += credit;
            totalDebt += credit;
        }

        // Give/take balance to Strategy, based on the difference between the reported gains,
        //  debt payment, debt,  and the credit increase we are offering
        // NOTE: This is just used to adjust the balance of tokens between the Strategy and
        // the Vault based on the Strategy's debt limit (as well as the Vault's).

        uint256 totalAvail = gain + debtPayment;
        // Credit surplus, give to Strategy
        if (totalAvail < credit) token.safeTransfer(address(strategy), credit - totalAvail);
        // Credit deficit, take from Strategy
        if (totalAvail > credit) token.safeTransferFrom(address(strategy), address(this), totalAvail - credit);

        // Update report times -> assessFees relies on the old lastReport value so must be called before it's updated
        _assessFees();
        strategies[strategy].lastReport = block.timestamp;
        lastReport = block.timestamp;

        emit StrategyReported(
            strategy,
            gain,
            loss,
            debtPayment,
            strategies[strategy].totalGain,
            strategies[strategy].totalLoss,
            strategies[strategy].totalDebt,
            credit,
            strategies[strategy].debtRatio
        );

        // If the strategy has been removed, it owes the vault all of its assets
        if (strategies[strategy].debtRatio == 0) return Strategy(strategy).estimatedTotalAssets();
        return debt;
    }

    function _reportLoss(Strategy strategy, uint256 loss) internal {
        uint256 strategyDebt = strategies[strategy].totalDebt;
        require(strategyDebt >= loss, "Strategy cannot lose more than it borrowed.");

        // Adjust our strategy's parameters by the loss
        strategies[strategy].totalLoss += loss;
        strategies[strategy].totalDebt = strategyDebt - loss;
        totalDebt -= loss;
    }

    function creditAvailable(Strategy strategy) public view returns (uint256) {
        uint256 vaultTotalAssets = vaultTVL();
        uint256 vaultDebtLimit = (debtRatio * vaultTotalAssets) / MAX_BPS;
        uint256 strategyDebtLimit = (strategies[strategy].debtRatio * vaultTotalAssets) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[strategy].totalDebt;

        // Exhausted credit line
        if (strategyDebtLimit <= strategyTotalDebt || vaultDebtLimit <= totalDebt) return 0;

        // Start with largest amount of debt that strategy can take
        uint256 available = strategyDebtLimit - strategyTotalDebt;

        // Adjust by the amount of credit that the vault can give
        available = Math.min(available, vaultDebtLimit - totalDebt);

        // Can only borrow up to what the contract has in reserve
        // NOTE: Running near 100% is discouraged
        available = Math.min(available, token.balanceOf(address(this)));

        // Adjust by min and max borrow limits (per harvest)
        // NOTE: min increase can be used to ensure that if a strategy has a minimum
        //       amount of capital needed to purchase a position, it's not given capital
        //       it can't make use of yet.
        // NOTE: max increase is used to make sure each harvest isn't bigger than what
        //       is authorized. This combined with adjusting min and max periods in
        //      `BaseStrategy` can be used to effect a "rate limit" on capital increase.
        if (available < strategies[strategy].minDebtPerHarvest) return 0;
        return Math.min(available, strategies[strategy].maxDebtPerHarvest);
    }

    function debtOutstanding(Strategy strategy) public view returns (uint256) {
        if (debtRatio == 0) return strategies[strategy].totalDebt;

        uint256 strategyDebtLimit = (strategies[strategy].debtRatio * vaultTVL()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[strategy].totalDebt;

        if (strategyTotalDebt <= strategyDebtLimit) return 0;
        return strategyTotalDebt - strategyDebtLimit;
    }

    function _assessFees() internal virtual {}

    // Rebalance strategies on this chain. No need for now. We can simply update strategy debtRatios
    function rebalance() external onlyGovernance {}
}
