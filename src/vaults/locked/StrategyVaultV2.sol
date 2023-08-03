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

        function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        // If vault is illiquid, lock shares
        if (!epochEnded) {
            uint govShares = _getWithdrawalFee(shares, owner);
            uint userShares = shares - govShares;
            _transfer({from: owner, to: address(debtEscrow), amount: userShares});
            _transfer({from: owner, to: governance, amount: govShares});
            debtEscrow.registerWithdrawalRequest(owner, userShares);
            emit DebtRegistration(caller, receiver, owner, userShares);
            return;
        }

        _withdrawFromStrategy(assets);

        // Slippage during liquidation means we might get less than `assets` amount of `_asset`
        assets = MathUpgradeable.min(_asset.balanceOf(address(this)), assets);
        uint256 assetsFee = _getWithdrawalFee(assets, owner);
        uint256 assetsToUser = assets - assetsFee;

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, assetsToUser);
        _asset.safeTransfer(governance, assetsFee);
    }


    function _getWithdrawalFee(uint256 assets, address owner) internal view virtual override returns (uint256) {
        uint256 feeBps;
        if (address(accessNft) != address(0) && accessNft.balanceOf(owner) > 0) {
            feeBps = withdrawalFeeWithNft;
        } else {
            feeBps = withdrawalFee;
        }
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
