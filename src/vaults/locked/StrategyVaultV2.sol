// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {NftGate} from "src/vaults/NftGate.sol";
import {HarvestStorage} from "src/vaults/HarvestStorage.sol";
import {VaultErrors} from "src/libs/VaultErrors.sol";

contract StrategyVaultV2 is StrategyVault, NftGate, HarvestStorage {
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
        return assets.mulDiv(feeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
    }

    function withdrawPerformanceFee() external virtual onlyGovernance {
        require(epochEnded, "SV: epoch not ended");
        uint256 fee = uint256(accumulatedPerformanceFee);

        _withdrawFromStrategy(fee);

        fee = MathUpgradeable.min(fee, _asset.balanceOf(address(this)));
        accumulatedPerformanceFee -= uint128(fee);

        _asset.safeTransfer(governance, fee);
        emit PerformanceFeeWithdrawn(fee);
    }

    function _updateTVL() internal virtual override {
        // Get the strategy's previous and current balance.
        uint256 prevBalance = strategyTVL;
        uint256 currentBalance = strategy.totalLockedValue();

        // Calculate profit made
        uint256 totalProfitAccrued = currentBalance > prevBalance ? currentBalance - prevBalance : 0;

        if (totalProfitAccrued > 0) {
            uint256 perfFee = totalProfitAccrued.mulDiv(performanceFeeBps, MAX_BPS, MathUpgradeable.Rounding.Up);
            accumulatedPerformanceFee += uint128(perfFee);
            totalProfitAccrued -= perfFee;
            currentBalance -= perfFee;
        }

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        maxLockedProfit = uint128(lockedProfit() + totalProfitAccrued);

        // Set strategy holdings to our new total.
        strategyTVL = currentBalance;

        // Assess fees (using old `lastHarvest`) and update the last harvest timestamp.
        _assessFees();
        lastHarvest = uint128(block.timestamp);
        emit Harvest(msg.sender);
    }
}
