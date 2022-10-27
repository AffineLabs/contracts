// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {BaseStrategy as Strategy} from "./BaseStrategy.sol";
import {AffineGovernable} from "./AffineGovernable.sol";
import {BridgeEscrow} from "./BridgeEscrow.sol";
import {WormholeRouter} from "./WormholeRouter.sol";
import {Multicallable} from "solady/src/utils/Multicallable.sol";
import {uncheckedInc} from "./Unchecked.sol";

/**
 * @notice A core contract to be inherited by the L1 and L2 vault contracts. This contract handles adding
 * and removing strategies, investing in (and divesting from) strategies, harvesting gains/losses, and
 * strategy liquidation.
 */
abstract contract BaseVault is AccessControl, AffineGovernable, Multicallable {
    using SafeTransferLib for ERC20;

    /**
     * UNDERLYING ASSET AND INITIALIZATION
     *
     */

    /// @notice The token that the vault takes in and gives to strategies, e.g. USDC
    ERC20 _asset;

    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    function baseInitialize(address _governance, ERC20 vaultAsset, address _wormholeRouter, BridgeEscrow _bridgeEscrow)
        internal
        virtual
    {
        governance = _governance;
        _asset = vaultAsset;
        wormholeRouter = _wormholeRouter;
        bridgeEscrow = _bridgeEscrow;

        // All roles use the default admin role
        // governance has the admin role and can grant/remove a role to any account
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(harvesterRole, governance);
        lastHarvest = uint128(block.timestamp);
    }

    /**
     * CROSS CHAIN REBALANCING
     *
     */

    /**
     * @notice A contract used for sending and receiving messages via wormhole.
     * @dev We use an address since we need to cast this to the L1 and L2 router types.
     */
    address public wormholeRouter;
    /// @notice A "BridgeEscrow" contract for sending and receiving `token` across a bridge.
    BridgeEscrow public bridgeEscrow;

    /**
     * @notice Update the address of the wormhole router.
     * @param _router The new router.
     */
    function setWormholeRouter(address _router) external onlyGovernance {
        wormholeRouter = _router;
    }
    /**
     * @notice Update the address of the bridge escrow.
     * @param _escrow The new escrow.
     */

    function setBridgeEscrow(BridgeEscrow _escrow) external onlyGovernance {
        bridgeEscrow = _escrow;
    }

    /**
     * AUTHENTICATION
     *
     */

    /// @notice Role with authority to call "harvest", i.e. update this vault's tvl
    bytes32 public constant harvesterRole = keccak256("HARVESTER");

    /**
     * WITHDRAWAL QUEUE
     *
     */

    uint8 public constant MAX_STRATEGIES = 20;

    /**
     * @notice An ordered array of strategies representing the withdrawal queue. The withdrawal queue is used
     * whenever the vault wants to pull money out of strategies (cross-chain rebalancing and user withdrawals)xw
     * @dev The first strategy in the array is withdrawn from first.
     * This is a list of the currently active strategies  (all non-zero addresses are active).
     */
    Strategy[MAX_STRATEGIES] public withdrawalQueue;

    /**
     * @notice Gets the full withdrawal queue.
     * @return The withdrawal queue.
     * @dev This gives easy access to the whole array (by default we can only get one index at a time)
     */
    function getWithdrawalQueue() external view returns (Strategy[MAX_STRATEGIES] memory) {
        return withdrawalQueue;
    }

    /**
     * @notice Sets a new withdrawal queue.
     * @param newQueue The new withdrawal queue.
     */
    function setWithdrawalQueue(Strategy[MAX_STRATEGIES] calldata newQueue) external onlyGovernance {
        // Ensure the new queue is not larger than the maximum queue size.
        require(newQueue.length <= MAX_STRATEGIES, "BV: queue too big");

        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(msg.sender, newQueue);
    }

    /**
     * @notice Swaps two indexes in the withdrawal queue.
     * @param index1 One index involved in the swap
     * @param index2 The other index involved in the swap.
     */
    function swapWithdrawalQueueIndexes(uint256 index1, uint256 index2) external onlyGovernance {
        // Get the (soon to be) new strategies at each index.
        Strategy newStrategy2 = withdrawalQueue[index1];
        Strategy newStrategy1 = withdrawalQueue[index2];

        // Swap the strategies at both indexes.
        withdrawalQueue[index1] = newStrategy1;
        withdrawalQueue[index2] = newStrategy2;

        emit WithdrawalQueueIndexesSwapped(msg.sender, index1, index2, newStrategy1, newStrategy2);
    }

    /**
     * @notice Emitted when the withdrawal queue is updated.
     * @param user The authorized user who triggered the set.
     * @param replacedWithdrawalQueue The new withdrawal queue.
     */
    event WithdrawalQueueSet(address indexed user, Strategy[MAX_STRATEGIES] replacedWithdrawalQueue);

    /**
     * @notice Emitted when the strategies at two indexes are swapped.
     * @param user The authorized user who triggered the swap.
     * @param index1 One index involved in the swap
     * @param index2 The other index involved in the swap.
     * @param newStrategy1 The strategy (previously at index2) that replaced index1.
     * @param newStrategy2 The strategy (previously at index1) that replaced index2.
     */
    event WithdrawalQueueIndexesSwapped(
        address indexed user,
        uint256 index1,
        uint256 index2,
        Strategy indexed newStrategy1,
        Strategy indexed newStrategy2
    );

    /**
     * STRATEGIES
     *
     */

    /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    uint256 public totalStrategyHoldings;

    struct StrategyInfo {
        bool isActive;
        uint16 tvlBps;
        uint232 balance;
    }
    /// @notice A map of strategy addresses to details about the strategy

    mapping(Strategy => StrategyInfo) public strategies;

    uint256 constant MAX_BPS = 10_000;
    /// @notice The number of bps of the vault's tvl which may be given to strategies (at most MAX_BPS)
    uint256 public totalBps;

    /// @notice Emitted when a strategy is added by governance
    event StrategyAdded(Strategy indexed strategy);
    /// @notice Emitted when a strategy is removed by governance
    event StrategyRemoved(Strategy indexed strategy);

    /**
     * @notice Add a strategy
     * @param strategy The strategy to add
     * @param tvlBps The number of bps of our tvl the strategy will get when funds are distributed to strategies
     */
    function addStrategy(Strategy strategy, uint16 tvlBps) external onlyGovernance {
        _increaseTVLBps(tvlBps);
        strategies[strategy] = StrategyInfo({isActive: true, tvlBps: tvlBps, balance: 0});
        //  Add strategy to withdrawal queue
        withdrawalQueue[withdrawalQueue.length - 1] = strategy;
        emit StrategyAdded(strategy);
        _organizeWithdrawalQueue();
    }

    /// @notice A helper function for increasing `totalBps`. Used when adding strategies or updating strategy allocs
    function _increaseTVLBps(uint256 tvlBps) internal {
        uint256 newTotalBps = totalBps + tvlBps;
        require(newTotalBps <= MAX_BPS, "BV: too many bps");
        totalBps = newTotalBps;
    }

    /**
     * @notice Push all zero addresses to the end of the array. This function is used whenever a strategy is
     * added or removed from the withdrawal queue
     * @dev Relative ordering of non-zero values is maintained.
     */
    function _organizeWithdrawalQueue() internal {
        // number or empty values we've seen iterating from left to right
        uint256 offset;

        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            Strategy strategy = withdrawalQueue[i];
            if (address(strategy) == address(0)) {
                offset += 1;
            } else if (offset > 0) {
                // index of first empty value seen takes on value of `strategy`
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = Strategy(address(0));
            }
        }
    }

    /**
     * @notice Remove a strategy from the withdrawal queue. Fully divest from the strategy.
     * @param strategy The strategy to remove
     * @dev  removeStrategy MUST be called with harvest via multicall. This helps get the most accurate tvl numbers
     * and allows us to add any realized profits to our lockedProfit
     */
    function removeStrategy(Strategy strategy) external onlyGovernance {
        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            if (strategy != withdrawalQueue[i]) {
                continue;
            }

            strategies[strategy].isActive = false;

            // The vault can re-allocate bps to a new strategy
            totalBps -= strategies[strategy].tvlBps;
            strategies[strategy].tvlBps = 0;

            // Remove strategy from withdrawal queue
            withdrawalQueue[i] = Strategy(address(0));
            emit StrategyRemoved(strategy);
            _organizeWithdrawalQueue();

            // Take all money out of strategy.
            _withdrawFromStrategy(strategy, strategy.totalLockedValue());
            break;
        }
    }

    /**
     * @notice Update tvl bps assigned to the given list of strategies
     * @param strategyList The list of strategies
     * @param strategyBps The new bps
     */
    function updateStrategyAllocations(Strategy[] calldata strategyList, uint16[] calldata strategyBps)
        external
        onlyRole(harvesterRole)
    {
        for (uint256 i = 0; i < strategyList.length; i = uncheckedInc(i)) {
            // Get the strategy at the current index.
            Strategy strategy = strategyList[i];

            // Ignore inactive (removed) strategies
            if (!strategies[strategy].isActive) {
                continue;
            }

            // update tvl bps
            totalBps -= strategies[strategy].tvlBps;
            _increaseTVLBps(strategyBps[i]);
            strategies[strategy].tvlBps = strategyBps[i];
        }
    }

    /**
     * STRATEGY DEPOSIT/WITHDRAWAL
     *
     */

    /**
     * @notice Emitted after the Vault deposits into a strategy contract.
     * @param strategy The strategy that was deposited into.
     * @param assets The amount of underlying tokens that were deposited.
     */
    event StrategyDeposit(Strategy indexed strategy, uint256 assets);

    /**
     * @notice Emitted after the Vault withdraws funds from a strategy contract.
     * @param strategy The strategy that was withdrawn from.
     * @param assets The amount of underlying tokens that were withdrawn.
     */
    event StrategyWithdrawal(Strategy indexed strategy, uint256 assets);

    /// @notice Deposit entire balance of `asset` into strategies according to each strategy's `tvlBps`.
    function _depositIntoStrategies() internal {
        uint256 totalBal = _asset.balanceOf(address(this));
        // All non-zero strategies are active
        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            Strategy strategy = withdrawalQueue[i];
            if (address(strategy) == address(0)) {
                break;
            }
            _depositIntoStrategy(strategy, (totalBal * strategies[strategy].tvlBps) / MAX_BPS);
        }
    }

    function _depositIntoStrategy(Strategy strategy, uint256 assets) internal {
        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += assets;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            strategies[strategy].balance += uint232(assets);
        }

        // Approve assets to the strategy so we can deposit.
        _asset.safeApprove(address(strategy), assets);

        // Deposit into the strategy, will revert upon failure
        strategy.invest(assets);
        emit StrategyDeposit(strategy, assets);
    }

    /**
     * @notice Withdraw a specific amount of underlying tokens from a strategy.
     * @dev This is "best effort" withdrawal. It could potentially withdraw nothing.
     * @param strategy The strategy to withdraw from.
     * @param assets  The amount of underlying tokens to withdraw.
     * @return The amount of underlying tokens withdrawn from the strategy.
     */
    function _withdrawFromStrategy(Strategy strategy, uint256 assets) internal returns (uint256) {
        // Withdraw from the strategy
        uint256 amountWithdrawn = _divest(strategy, assets);

        // Without this the next harvest would count the withdrawal as a loss.
        // We update the balance to the current tvl because a withdrawal can reduce the tvl by more than the amount
        // withdrawn (e.g. fees during a swap)
        uint256 oldStratTVL = strategies[strategy].balance;
        uint256 newStratTvl = strategy.totalLockedValue();
        strategies[strategy].balance = uint232(newStratTvl);

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            // If we haven't harvested in a long time, newStratTvl could be smaller than oldStratTvl, even with the withdrawal
            totalStrategyHoldings -= oldStratTVL > newStratTvl ? oldStratTVL - newStratTvl : 0;
        }

        emit StrategyWithdrawal(strategy, amountWithdrawn);
        return amountWithdrawn;
    }

    /// @notice A small wrapper around divest(). We try-catch to make sure that a bad strategy does not pause withdrawals.
    function _divest(Strategy strategy, uint256 assets) internal returns (uint256) {
        try strategy.divest(assets) returns (uint256 amountDivested) {
            return amountDivested;
        } catch {
            return 0;
        }
    }

    /**
     * HARVESTING
     *
     */

    /**
     * @notice A timestamp representing when the most recent harvest occurred.
     * @dev Since the time since the last harvest is used to calculate management fees, this is set
     * to `block.timestamp` (instead of 0) during initialization.
     */
    uint128 public lastHarvest;
    /// @notice The amount of profit *originally* locked after harvesting from a strategy
    uint128 public maxLockedProfit;
    /// @notice Amount of time in seconds that profit takes to fully unlock. See lockedProfit().
    uint256 public constant lockInterval = 24 hours;
    uint256 public constant SECS_PER_YEAR = 365 days;

    /**
     * @notice Emitted after a successful harvest.
     * @param user The authorized user who triggered the harvest.
     * @param strategies The trusted strategies that were harvested.
     */
    event Harvest(address indexed user, Strategy[] strategies);

    /**
     * @notice Harvest a set of trusted strategies.
     * @param strategyList The trusted strategies to harvest.
     * @dev Will always revert if profit from last harvest has not finished unlocking.
     */
    function harvest(Strategy[] calldata strategyList) external onlyRole(harvesterRole) {
        // Profit must not be unlocking
        require(block.timestamp >= lastHarvest + lockInterval, "BV: profit unlocking");

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

        // Will revert if any of the specified strategies are untrusted.
        for (uint256 i = 0; i < strategyList.length; i = uncheckedInc(i)) {
            // Get the strategy at the current index.
            Strategy strategy = strategyList[i];

            // Ignore inactive (removed) strategies
            if (!strategies[strategy].isActive) {
                continue;
            }

            // Get the strategy's previous and current balance.
            uint232 balanceLastHarvest = strategies[strategy].balance;
            uint256 balanceThisHarvest = strategy.totalLockedValue();

            // Update the strategy's stored balance.
            strategies[strategy].balance = uint232(balanceThisHarvest);

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
        maxLockedProfit = uint128(lockedProfit() + totalProfitAccrued);

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Assess fees (using old lastHarvest) and update the last harvest timestamp.
        _assessFees();
        lastHarvest = uint128(block.timestamp);

        emit Harvest(msg.sender, strategyList);
    }

    /**
     * @notice Current locked profit amount.
     * @dev Profit unlocks uniformly over `lockInterval` seconds after the last harvest
     */
    function lockedProfit() public view virtual returns (uint256) {
        if (block.timestamp >= lastHarvest + lockInterval) {
            return 0;
        }

        uint256 unlockedProfit = (maxLockedProfit * (block.timestamp - lastHarvest)) / lockInterval;
        return maxLockedProfit - unlockedProfit;
    }

    /// @notice The total amount of the underlying asset the vault has.
    function vaultTVL() public view returns (uint256) {
        return _asset.balanceOf(address(this)) + totalStrategyHoldings;
    }

    /**
     * @notice Emitted whenever the vault withdraws from multiple strategies
     * @dev We liquidate from cross chain rebalancing
     * @param amountRequested The amount we wanted to liquidate
     * @param amountLiquidated The amount we actually liquidated
     */
    event Liquidation(uint256 amountRequested, uint256 amountLiquidated);

    /**
     * @notice Withdraw `amount` of underlying asset from strategies.
     * @dev Always check the return value when using this function, we might not liquidate anything!
     * @param amount The amount we want to liquidate
     * @return The amount we actually liquidated
     */
    function _liquidate(uint256 amount) internal returns (uint256) {
        uint256 amountLiquidated;
        uint256 length = withdrawalQueue.length;
        for (uint256 i = 0; i < length; i = uncheckedInc(i)) {
            Strategy strategy = withdrawalQueue[i];
            if (address(strategy) == address(0)) {
                break;
            }

            uint256 balance = _asset.balanceOf(address(this));
            if (balance >= amount) {
                break;
            }

            uint256 amountNeeded = amount - balance;
            amountNeeded = Math.min(amountNeeded, strategies[strategy].balance);

            // Force withdraw of token from strategy
            uint256 withdrawn = _withdrawFromStrategy(strategy, amountNeeded);
            amountLiquidated += withdrawn;
        }
        emit Liquidation(amount, amountLiquidated);
        return amountLiquidated;
    }

    /**
     * @notice Assess fees.
     * @dev This is called during harvest() to assess management fees.
     */
    function _assessFees() internal virtual {}

    /// @notice  Rebalance strategies according to given tvl bps
    function rebalance() external onlyRole(harvesterRole) {
        uint256 tvl = vaultTVL();

        // Loop through all strategies. Divesting from those whose tvl is too high,
        // Invest in those whose tvl is too low

        // MAX_STRATEGIES is always equal to withdrawalQueue.length
        uint256[MAX_STRATEGIES] memory amountsToInvest;

        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            Strategy strategy = withdrawalQueue[i];
            if (address(strategy) == address(0)) {
                break;
            }

            uint256 idealStrategyTVL = (tvl * strategies[strategy].tvlBps) / MAX_BPS;
            uint256 currStrategyTVL = strategy.totalLockedValue();
            if (idealStrategyTVL < currStrategyTVL) {
                _withdrawFromStrategy(strategy, currStrategyTVL - idealStrategyTVL);
            }
            if (idealStrategyTVL > currStrategyTVL) {
                amountsToInvest[i] = idealStrategyTVL - currStrategyTVL;
            }
        }

        // Loop through the strategies to invest in, and invest in them
        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            uint256 amountToInvest = amountsToInvest[i];
            if (amountToInvest == 0) {
                continue;
            }

            // We aren't guaranteed that the vault has `amountToInvest` since there can be slippage
            // when divesting from strategies
            // NOTE: Strategies closer to the start of the queue are more likely to get the exact
            // amount of money needed
            amountToInvest = Math.min(amountToInvest, _asset.balanceOf(address(this)));
            if (amountToInvest == 0) {
                break;
            }
            // Deposit into strategy, making sure to not count this investment as a profit
            _depositIntoStrategy(withdrawalQueue[i], amountToInvest);
        }
    }
}
