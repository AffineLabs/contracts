// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

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
        Staging _staging
    ) public {
        governance = _governance;
        token = _token;
        wormhole = _wormhole;

        _grantRole(bankerRole, governance);
        _grantRole(queueOperatorRole, governance);

        staging = _staging;
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
    bytes32 public constant queueOperatorRole = keccak256("QUEUE_OPERATOR");

    /** WITHDRAWAL QUEUE
     **************************************************************************/

    uint8 public constant MAX_STRATEGIES = 20;

    /// @notice An ordered array of strategies representing the withdrawal queue.
    /// @dev The first strategy in the array is withdrawn from first.
    /// @dev This is a list of the currently active strategies  (all non-zero addresses are active)
    Strategy[MAX_STRATEGIES] public withdrawalQueue;

    /// @notice Gets the full withdrawal queue.
    /// @return The withdrawal queue.
    /// @dev This is provided because Solidity converts public arrays into index getters,
    /// but we need a way to allow external contracts and users to access the whole array.
    function getWithdrawalQueue() external view returns (Strategy[MAX_STRATEGIES] memory) {
        return withdrawalQueue;
    }

    /// @notice Sets a new withdrawal queue.
    /// @param newQueue The new withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalQueue(Strategy[MAX_STRATEGIES] calldata newQueue) external onlyRole(queueOperatorRole) {
        // Ensure the new queue is not larger than the maximum queue size.
        require(newQueue.length <= MAX_STRATEGIES, "QUEUE_TOO_BIG");

        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(msg.sender, newQueue);
    }

    /// @notice Swaps two indexes in the withdrawal queue.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    function swapWithdrawalQueueIndexes(uint256 index1, uint256 index2) external onlyRole(queueOperatorRole) {
        // Get the (soon to be) new strategies at each index.
        Strategy newStrategy2 = withdrawalQueue[index1];
        Strategy newStrategy1 = withdrawalQueue[index2];

        // Swap the strategies at both indexes.
        withdrawalQueue[index1] = newStrategy1;
        withdrawalQueue[index2] = newStrategy2;

        emit WithdrawalQueueIndexesSwapped(msg.sender, index1, index2, newStrategy1, newStrategy2);
    }

    /// @notice Emitted when the withdrawal queue is updated.
    /// @param user The authorized user who triggered the set.
    /// @param replacedWithdrawalQueue The new withdrawal queue.
    event WithdrawalQueueSet(address indexed user, Strategy[MAX_STRATEGIES] replacedWithdrawalQueue);

    /// @notice Emitted when the strategies at two indexes are swapped.
    /// @param user The authorized user who triggered the swap.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    /// @param newStrategy1 The strategy (previously at index2) that replaced index1.
    /// @param newStrategy2 The strategy (previously at index1) that replaced index2.
    event WithdrawalQueueIndexesSwapped(
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
        //  Add strategy to withdrawal queue
        withdrawalQueue[withdrawalQueue.length - 1] = strategy;
        emit StrategyAdded(strategy);
        _organizeWithdrawalQueue();
    }

    /// @notice Push all zero addresses to the end of the array
    /// @dev Relative ordering of non-zero values is maintained.
    function _organizeWithdrawalQueue() internal {
        // number or empty values we've seen iterating from left to right
        uint256 offset;

        uint256 length = withdrawalQueue.length;
        for (uint256 i = 0; i < length; i++) {
            Strategy strategy = withdrawalQueue[i];
            if (address(strategy) == address(0)) offset += 1;
            else if (offset > 0) {
                // idx of first empty value seen takes on value of `strategy`
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = Strategy(address(0));
            }
        }
    }

    function removeStrategy(Strategy strategy) external onlyGovernance {
        // TODO: consider withdrawaing all possible money from a strategy before popping it from withdrawal queue

        //  Remove from withdrawal queue
        uint256 length = withdrawalQueue.length;
        for (uint256 i = 0; i < length; i++) {
            if (strategy == withdrawalQueue[i]) {
                strategies[strategy].isActive = false;
                withdrawalQueue[i] = Strategy(address(0));
                emit StrategyRemoved(strategy);
                _organizeWithdrawalQueue();
                break;
            }
        }
    }

    /** STRATEGY DEPOSIT/WITHDRAWAL
     **************************************************************************/

    /// @notice Emitted after the Vault deposits into a strategy contract.
    /// @param strategy The strategy that was deposited into.
    /// @param tokenAmount The amount of underlying tokens that were deposited.
    event StrategyDeposit(Strategy indexed strategy, uint256 tokenAmount);

    /// @notice Emitted after the Vault withdraws funds from a strategy contract.
    /// @param user The authorized user who triggered the withdrawal.
    /// @param strategy The strategy that was withdrawn from.
    /// @param tokenAmount The amount of underlying tokens that were withdrawn.
    event StrategyWithdrawal(address indexed user, Strategy indexed strategy, uint256 tokenAmount);

    /// @notice Deposit a specific amount of token into a trusted strategy.
    /// @param strategy The trusted strategy to deposit into.
    /// @param tokenAmount The amount of underlying tokens to deposit.
    function depositIntoStrategy(Strategy strategy, uint256 tokenAmount) internal {
        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += tokenAmount;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            strategies[strategy].balance += tokenAmount;
        }

        // Approve tokenAmount to the strategy so we can deposit.
        token.safeApprove(address(strategy), tokenAmount);

        // Deposit into the strategy, will revert upon failure
        strategy.invest(tokenAmount);
        emit StrategyDeposit(strategy, tokenAmount);
    }

    function depositIntoStrategies() internal {
        // get all strategies that are active with a simple loop
        // call depositIntoStrategy (can probably get rid of the function call)
    }

    /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    /// @param strategy The strategy to withdraw from.
    /// @param tokenAmount  The amount of underlying tokens to withdraw.
    /// @dev Withdrawing from a strategy will not remove it from the withdrawal queue.
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
            Strategy strategy = withdrawalQueue[i];
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
