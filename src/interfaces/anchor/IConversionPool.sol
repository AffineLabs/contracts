// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

interface IConversionPool {
    function deposit(uint256 _amount) external;

    function deposit(uint256 _amount, uint256 _minAmountOut) external;

    function redeem(uint256 _amount) external;

    function redeem(uint256 _amount, uint256 _minAmountOut) external;
}
