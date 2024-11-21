// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {VaultV2, MathUpgradeable, SafeTransferLib, ERC20} from "src/vaults/VaultV2.sol";
import {ProfitReserveStorage} from "src/vaults/ProfitReserveStorage.sol";

import {BaseStrategy as Strategy} from "src/strategies/BaseStrategy.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";

contract ProfitReserveVaultV2 is VaultV2, ProfitReserveStorage {
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;

    function harvest(Strategy[] calldata strategyList) external virtual override onlyRole(HARVESTER) {
        // Profit must not be unlocking
        require(block.timestamp >= lastHarvest + LOCK_INTERVAL, "BV: profit unlocking");

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

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

            uint256 strategyProfit = balanceThisHarvest > balanceLastHarvest
                ? balanceThisHarvest - balanceLastHarvest // Profits since last harvest.
                : 0;

            // reserver some profits for later use.

            uint256 reservedProfit = strategyProfit.mulDiv(profitReserveBps, MAX_BPS, MathUpgradeable.Rounding.Down);
            // Update the strategy's stored balance.
            strategies[strategy].balance = uint232(balanceThisHarvest - reservedProfit);

            // Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
            // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
            newTotalStrategyHoldings =
                newTotalStrategyHoldings + balanceThisHarvest - balanceLastHarvest - reservedProfit;

            totalProfitAccrued += (strategyProfit - reservedProfit);
        }

        if (totalProfitAccrued > 0) {
            uint256 perfFee = totalProfitAccrued.mulDiv(performanceFeeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
            accumulatedPerformanceFee += uint128(perfFee);
            totalProfitAccrued -= perfFee;
            newTotalStrategyHoldings -= perfFee;
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
}
