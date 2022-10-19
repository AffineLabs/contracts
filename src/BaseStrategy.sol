// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {BaseVault} from "./BaseVault.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

/// @notice Base strategy contract
abstract contract BaseStrategy {
    using SafeTransferLib for ERC20;

    constructor(BaseVault _vault) {
        vault = _vault;
        asset = ERC20(_vault.asset());
    }

    ///@notice The vault which owns this contract
    BaseVault public immutable vault;

    modifier onlyVault() {
        require(msg.sender == address(vault), "ONLY_VAULT");
        _;
    }

    /// @notice Returns the underlying ERC20 asset the strategy accepts.
    ERC20 public immutable asset;

    /// @notice Strategy's balance of underlying asset.
    /// @return assets Strategy's balance.
    function balanceOfAsset() public view returns (uint256 assets) {
        assets = asset.balanceOf(address(this));
    }

    /// @notice Deposit vault's underlying asset into strategy.
    /// @param amount The amount to invest.
    /// @dev This function must revert if investment fails.
    function invest(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _afterInvest(amount);
    }

    /// @notice After getting money from the vault, do something with it.
    /// @param amount The amount received from the vault.
    /// @dev Since investment is often gas-intensive and may require off-chain data, this will often be unimplemented.
    /// @dev Strategists will call custom functions for handling deployment of capital.
    function _afterInvest(uint256 amount) internal virtual {}

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
