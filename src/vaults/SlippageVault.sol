// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Vault} from "src/vaults/Vault.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {NftGate} from "src/vaults/NftGate.sol";
import {HarvestStorage} from "src/vaults/HarvestStorage.sol";
import {BaseStrategy as Strategy} from "src/strategies/BaseStrategy.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";
import {VaultErrors} from "src/libs/VaultErrors.sol";

contract SlippageVault is VaultV2 {
    using SafeTransferLib for ERC20;
    using MathUpgradeable for uint256;

    /**
     * @dev See {IERC4262-deposit}.
     */
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        _harvestAll();
        uint256 shares = previewDeposit(assets);
        uint256 oldSupply = totalSupply();
        _deposit(_msgSender(), receiver, assets, shares);
        return totalSupply() - oldSupply;
    }

    /**
     * @dev See {IERC4262-mint}.
     */
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        _harvestAll();
        uint256 assets = previewMint(shares);

        uint256 oldTVL = vaultTVL();
        _deposit(_msgSender(), receiver, assets, shares);

        return vaultTVL() - oldTVL;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _checkNft(receiver);
        if (shares == 0) revert VaultErrors.ZeroShares();

        uint256 oldTVL = vaultTVL();
        uint256 assetsPerShare = _convertToAssets(10 ** decimals(), MathUpgradeable.Rounding.Up);

        _asset.safeTransferFrom(_msgSender(), address(this), assets);
        _depositIntoStrategies(assets);

        // assets after investment
        uint256 investedAssets = vaultTVL() - oldTVL;
        uint256 receivableShares =
            investedAssets.mulDiv(10 ** decimals(), assetsPerShare, MathUpgradeable.Rounding.Down);

        _mint(receiver, receivableShares);

        emit Deposit(caller, receiver, investedAssets, receivableShares);
    }

    function _getWithdrawalFee(uint256 assets, address owner) internal view virtual override returns (uint256) {
        uint256 feeBps = withdrawalFee;
        if (nftDiscountActive && accessNft.balanceOf(owner) > 0) feeBps = withdrawalFeeWithNft;
        return assets.mulDiv(feeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
    }

    function _harvestAll() internal {
        // Profit must not be unlocking
        // require(block.timestamp >= lastHarvest + LOCK_INTERVAL, "BV: profit unlocking");

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            // Get the strategy at the current index.

            Strategy strategy = withdrawalQueue[i];

            if (address(strategy) == address(0)) {
                break;
            }
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
            // Update max unlocked profit based on any remaining locked profit plus new profit.
            maxLockedProfit = uint128(lockedProfit() + totalProfitAccrued);
        } else if (newTotalStrategyHoldings < oldTotalStrategyHoldings) {
            // updating locked profit with loss
            if (lockedProfit() > (oldTotalStrategyHoldings - newTotalStrategyHoldings)) {
                // Update max unlocked profit removing the loss
                maxLockedProfit = uint128(lockedProfit() - (oldTotalStrategyHoldings - newTotalStrategyHoldings));
            }
        }

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Assess fees (using old lastHarvest) and update the last harvest timestamp.
        _assessFees();
        lastHarvest = uint128(block.timestamp);
    }

    function harvest(Strategy[] calldata strategyList) external virtual override onlyRole(HARVESTER) {
        // Profit must not be unlocking
        // require(block.timestamp >= lastHarvest + LOCK_INTERVAL, "BV: profit unlocking");

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
            // Update max unlocked profit based on any remaining locked profit plus new profit.
            maxLockedProfit = uint128(lockedProfit() + totalProfitAccrued);
        } else if (newTotalStrategyHoldings < oldTotalStrategyHoldings) {
            // updating locked profit with loss
            if (lockedProfit() > (oldTotalStrategyHoldings - newTotalStrategyHoldings)) {
                // Update max unlocked profit removing the loss
                maxLockedProfit = uint128(lockedProfit() - (oldTotalStrategyHoldings - newTotalStrategyHoldings));
            }
        }

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Assess fees (using old lastHarvest) and update the last harvest timestamp.
        _assessFees();
        lastHarvest = uint128(block.timestamp);
        emit Harvest(msg.sender, strategyList);
    }

    // @dev this investment will update the strategy holdings with tvl of strategy
    // @dev this will check for investment loss.

    function _depositIntoStrategy(Strategy strategy, uint256 assets) internal virtual override {
        // Don't allow empty investments
        if (assets == 0) return;

        // Approve assets to the strategy so we can deposit.
        _asset.safeApprove(address(strategy), assets);

        uint256 oldStrategyTVL = strategy.totalLockedValue();
        // Deposit into the strategy, will revert upon failure
        strategy.invest(assets);

        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings = (totalStrategyHoldings + strategy.totalLockedValue()) - oldStrategyTVL;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            strategies[strategy].balance = uint232(strategy.totalLockedValue());
        }

        emit StrategyDeposit(strategy, assets);
    }
}
