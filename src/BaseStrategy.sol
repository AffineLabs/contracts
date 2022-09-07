// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {BaseVault} from "./BaseVault.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

/// @notice Base strategy contract
abstract contract BaseStrategy {
    using SafeTransferLib for ERC20;

    ///@notice The vault which owns this contract
    BaseVault public vault;

    modifier onlyVault() {
        require(msg.sender == address(vault), "ONLY_VAULT");
        _;
    }

    /// @notice Returns the underlying ERC20 asset the strategy accepts.
    ERC20 public asset;

    /// @notice Strategy's balance of underlying asset.
    /// @return Strategy's balance.
    function balanceOfAsset() external view virtual returns (uint256);

    /// @notice Deposit vault's underlying asset into strategy.
    /// @param amount The amount to invest.
    /// @dev This function must revert if investment fails.
    function invest(uint256 amount) external virtual;

    /// @notice Withdraw vault's underlying asset from strategy.
    /// @param amount The amount to withdraw.
    /// @dev This function will not revert if we get less than `amount` out of the strategy
    /// @return The amount of `asset` divested from the strategy
    function divest(uint256 amount) external virtual returns (uint256);

    /// @notice The total amount of `asset` that the strategy is managing
    /// @dev This should not overestimate, and should account for slippage during divestment
    /// @return The strategy tvl
    function totalLockedValue() external virtual returns (uint256);

    function sweep(ERC20 rewardToken) external {
        require(msg.sender == vault.governance(), "ONLY_GOVERNANCE");
        require(rewardToken != asset, "!asset");
        rewardToken.safeTransfer(vault.governance(), rewardToken.balanceOf(address(this)));
    }
}
