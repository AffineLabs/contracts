// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface IConversionPool {
    function deposit(uint256 _amount) external;

    function deposit(uint256 _amount, uint256 _minAmountOut) external;

    function redeem(uint256 _amount) external;

    function redeem(uint256 _amount, uint256 _minAmountOut) external;
}
