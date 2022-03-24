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

contract BaseVault is AccessControl {
    using SafeTransferLib for ERC20;

    /** UNDERLYING ASSET AND INITIALIZATION
     **************************************************************************/

    /// @notice The token that the vault takes in and gives to strategies, e.g. USDC
    ERC20 public token;

    // TODO: handle access control in a better way
    function init(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer,
        bytes32 salt
    ) public {
        governance = _governance;
        token = _token;
        wormhole = _wormhole;

        _grantRole(bankerRole, governance);
        _grantRole(stackOperatorRole, governance);

        bytes memory bytecode = type(Staging).creationCode;
        staging = Staging(create2Deployer.deploy(0, salt, bytecode));
        staging.initialize(address(this), _wormhole, _token);
    }

    /** CROSS CHAIN MESSAGE PASSING AND REBALANCING
     **************************************************************************/

    // Wormhole contract for sending/receiving messages
    IWormhole public wormhole;
    Staging public staging;

    /** AUTHENTICATION
     **************************************************************************/

    address public governance;
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only Governance.");
        _;
    }
    bytes32 public constant bankerRole = keccak256("BANKER");
    bytes32 public constant stackOperatorRole = keccak256("STACK_OPERATOR");

    /** WITHDRAWAL STACK
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
    /// @dev Useful for removing a strategy from the stack
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

    /** STRATEGIES
     **************************************************************************/

    /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    /// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
    uint256 public totalStrategyHoldings;

    struct StrategyInfo {
        bool isActive;
        uint256 balance;
        uint256 totalGain;
        uint256 totalLoss;
    }
    mapping(Strategy => StrategyInfo) public strategies;

    event StrategyAdded(Strategy indexed strategy);
    event StrategyRemoved(Strategy indexed strategy);

    function addStrategy(Strategy strategy) external onlyGovernance {
        strategies[strategy].isActive = true;

        //  Add strategy to withdrawal stack
        emit StrategyAdded(strategy);
        _pushToWithdrawalStack(strategy);
    }

    function removeStrategy(Strategy strategy) external onlyGovernance {
        strategies[strategy].isActive = false;

        //  Remove from withdrawal stack
        emit StrategyRemoved(strategy);

        // TODO: consider withdrawaing all possible money from a strategy before popping it from withdrawal stack
        // We don't need to actually remove the bad strategy from the withdrawal stack here since we only withdraw from
        // active strategies
    }

    /** STRATEGY DEPOSIT/WITHDRAWAL
     **************************************************************************/

    /// @notice Emitted after the Vault deposits into a strategy contract.
    /// @param user The authorized user who triggered the deposit.
    /// @param strategy The strategy that was deposited into.
    /// @param tokenAmount The amount of underlying tokens that were deposited.
    event StrategyDeposit(address indexed user, Strategy indexed strategy, uint256 tokenAmount);

    /// @notice Emitted after the Vault withdraws funds from a strategy contract.
    /// @param user The authorized user who triggered the withdrawal.
    /// @param strategy The strategy that was withdrawn from.
    /// @param tokenAmount The amount of underlying tokens that were withdrawn.
    event StrategyWithdrawal(address indexed user, Strategy indexed strategy, uint256 tokenAmount);

    /// @notice Deposit a specific amount of token into a trusted strategy.
    /// @param strategy The trusted strategy to deposit into.
    /// @param tokenAmount The amount of underlying tokens to deposit.
    function depositIntoStrategy(Strategy strategy, uint256 tokenAmount) external onlyRole(bankerRole) {
        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += tokenAmount;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            strategies[strategy].balance += tokenAmount;
        }

        emit StrategyDeposit(msg.sender, strategy, tokenAmount);

        // Approve tokenAmount to the strategy so we can deposit.
        token.safeApprove(address(strategy), tokenAmount);

        // Deposit into the strategy, will revert upon failure
        strategy.invest(tokenAmount);
    }

    /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    /// @param strategy The strategy to withdraw from.
    /// @param tokenAmount  The amount of underlying tokens to withdraw.
    /// @dev Withdrawing from a strategy will not remove it from the withdrawal stack.
    /// @return The amount withdrawn from the strategy.
    function withdrawFromStrategy(Strategy strategy, uint256 tokenAmount)
        external
        onlyRole(bankerRole)
        returns (uint256)
    {
        // NOTE: this violates check-effects-interactions, but this is fine since only trusted
        // strategies will be added

        // Withdraw from the strategy
        uint256 amountWithdrawn = strategy.divest(tokenAmount);
        // Without this the next harvest would count the withdrawal as a loss.
        strategies[strategy].balance -= amountWithdrawn;

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= amountWithdrawn;
        }

        emit StrategyWithdrawal(msg.sender, strategy, amountWithdrawn);

        return amountWithdrawn;
    }

    /** HARVESTING
     **************************************************************************/

    /// @notice A timestamp representing when the most recent harvest occurred.
    uint256 public lastHarvest;
    // @notice The amount of profit *originally* locked after harvesting from a strategy
    uint256 public maxLockedProfit;
    // Amount of time in seconds that profit takes to fully unlock see lockedProfit().
    uint256 public constant lockInterval = 3 hours;
    uint256 public constant SECS_PER_YEAR = 365 days;

    /// @notice Emitted after a successful harvest.
    /// @param user The authorized user who triggered the harvest.
    /// @param strategies The trusted strategies that were harvested.
    event Harvest(address indexed user, Strategy[] strategies);

    /// @notice Harvest a set of trusted strategies.
    /// @param strategyList The trusted strategies to harvest.
    /// @dev Will always revert if profit from last harvest has not finished unlocking.
    function harvest(Strategy[] calldata strategyList) external onlyRole(bankerRole) {
        // Profit must not be unlocking
        require(block.timestamp >= lastHarvest + lockInterval, "PROFIT_UNLOCKING");

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

        // Will revert if any of the specified strategies are untrusted.
        for (uint256 i = 0; i < strategyList.length; i++) {
            // Get the strategy at the current index.
            Strategy strategy = strategyList[i];

            // Ignore inactive (removed) strategies
            if (!strategies[strategy].isActive) {
                continue;
            }

            // Get the strategy's previous and current balance.
            uint256 balanceLastHarvest = strategies[strategy].balance;
            uint256 balanceThisHarvest = strategy.totalLockedValue();

            // Update the strategy's stored balance.
            strategies[strategy].balance = balanceThisHarvest;

            // Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
            // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
            newTotalStrategyHoldings = newTotalStrategyHoldings + balanceThisHarvest - balanceLastHarvest;

            unchecked {
                // Update the total profit accrued while counting losses as zero profit.
                // Cannot overflow as we already increased total holdings without reverting.
                totalProfitAccrued += balanceThisHarvest > balanceLastHarvest
                    ? balanceThisHarvest - balanceLastHarvest // Profits since last harvest.
                    : 0; // If the strategy registered a net loss we don't have any new profit.
            }
        }

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        maxLockedProfit = lockedProfit() + totalProfitAccrued;

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Assess fees (using old lastHarvest) and update the last harvest timestamp.
        _assessFees();
        lastHarvest = block.timestamp;

        emit Harvest(msg.sender, strategyList);
    }

    /// @notice Current locked profit amount.
    /// @dev Profit unlocks uniformly over `lockInterval` seconds after the last harvest
    function lockedProfit() public view returns (uint256) {
        if (block.timestamp >= lastHarvest + lockInterval) return 0;

        uint256 unlockedProfit = (maxLockedProfit * (block.timestamp - lastHarvest)) / lockInterval;
        return maxLockedProfit - unlockedProfit;
    }

    function vaultTVL() public view returns (uint256) {
        return token.balanceOf(address(this)) + totalStrategyHoldings;
    }

    event Liquidation(uint256 amountRequested, uint256 amountLiquidated);

    /// @notice Try to get `amount` out of the strategies.
    function liquidate(uint256 amount) external onlyGovernance {
        _liquidate(amount);
    }

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
            amountNeeded = Math.min(amountNeeded, strategies[strategy].balance);

            // Force withdraw of token from strategy
            Strategy(strategy).divest(amountNeeded);
            uint256 withdrawn = token.balanceOf(address(this)) - balance;

            // update debts, amountLiquidated
            // Reduce the Strategy's debt by the amount withdrawn ("realized returns")
            // NOTE: This doesn't add to totalGain as it's not earned by "normal means"
            amountLiquidated += withdrawn;
        }
        emit Liquidation(amount, amountLiquidated);
        return amountLiquidated;
    }

    uint256 public constant MAX_BPS = 10_000;

    function _assessFees() internal virtual {}

    // Rebalance strategies on this chain.
    function rebalance() external onlyGovernance {}
}
