// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {L2Vault} from "src/vaults/cross-chain-vault/audited/L2Vault.sol";
import {NftGate} from "src/vaults/NftGate.sol";
import {HarvestStorage} from "src/vaults/HarvestStorage.sol";
import {BaseStrategy as Strategy} from "src/strategies/audited/BaseStrategy.sol";
import {uncheckedInc} from "src/libs/audited/Unchecked.sol";

import {VaultErrors} from "src/libs/VaultErrors.sol";
import {RebalanceStorage} from "src/vaults/cross-chain-vault/RebalanceStorage.sol";

contract L2VaultV2 is L2Vault, NftGate, HarvestStorage, RebalanceStorage {
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _checkNft(receiver);

        if (shares == 0) revert VaultErrors.ZeroShares();
        _mint(receiver, shares);
        _asset.safeTransferFrom(caller, address(this), assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _getWithdrawalFee(uint256 assets, address owner) internal view virtual override returns (uint256) {
        uint256 feeBps = withdrawalFee;
        if (nftDiscountActive && accessNft.balanceOf(owner) > 0) feeBps = withdrawalFeeWithNft;

        uint256 fee = assets.mulDiv(feeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
        if (_msgSender() == address(emergencyWithdrawalQueue)) fee = MathUpgradeable.max(fee, ewqMinFee);

        return fee;
    }

    function harvest(Strategy[] calldata strategyList) external virtual override onlyRole(HARVESTER) {
        // Profit must not be unlocking
        if (block.timestamp < lastHarvest + LOCK_INTERVAL) revert VaultErrors.ProfitUnlocking();

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

    function withdrawPerformanceFee() external virtual onlyGovernance {
        uint256 fee = uint256(accumulatedPerformanceFee);
        _liquidate(fee);

        fee = MathUpgradeable.min(fee, _asset.balanceOf(address(this)));
        accumulatedPerformanceFee -= uint128(fee);

        _asset.safeTransfer(governance, fee);
        emit PerformanceFeeWithdrawn(fee);
    }

    function rebalance() external virtual override onlyRole(HARVESTER) {
        rebalanceModule.rebalance();
    }
}
