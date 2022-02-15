// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

/// @notice Base strategy contract
abstract contract Strategy {
    /// @notice Returns the underlying ERC20 token the strategy accepts.
    /// @return The underlying ERC20 token the strategy accepts.
    function token() external virtual returns (ERC20);

    /// @notice Strategy's balance of underlying token.
    /// @return Strategy's balance.
    function balanceOfToken() external virtual returns (uint256);

    /// @notice Deposit vault's underlying token into strategy.
    /// @param amount The amount to invest.
    /// @dev This function must revert if investment fails.
    function invest(uint256 amount) external virtual;

    /// @notice Withdraw vault's underlying token from strategy.
    /// @param amount The amount to withdraw.
    /// @dev This function must revert if divestment fails.
    function divest(uint256 amount) external virtual;
}
