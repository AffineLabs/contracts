// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { BaseVault } from "./BaseVault.sol";

/// @notice Base strategy contract
abstract contract BaseStrategy {
    ///@notice The vault which owns this contract
    BaseVault public vault;
    modifier onlyVault() {
        require(msg.sender == address(vault), "ONLY_VAULT");
        _;
    }

    /// @notice Returns the underlying ERC20 token the strategy accepts.
    ERC20 public token;

    /// @notice Strategy's balance of underlying token.
    /// @return Strategy's balance.
    function balanceOfToken() external view virtual returns (uint256);

    /// @notice Deposit vault's underlying token into strategy.
    /// @param amount The amount to invest.
    /// @dev This function must revert if investment fails.
    function invest(uint256 amount) external virtual;

    /// @notice Withdraw vault's underlying token from strategy.
    /// @param amount The amount to withdraw.
    /// @dev This function will not revert if we get less than `amount` out of the strategy
    /// @return The amount of `token` divested from the strategy
    function divest(uint256 amount) external virtual returns (uint256);

    /// @notice The total amount of `token` that the strategy is managing
    /// @dev This should not overestimate, and should account for slippage during divestment
    function totalLockedValue() external virtual returns (uint256);
}
