// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IStaging {
    function initializeL1(address manager) external;

    function initialize(
        address vault,
        address wormhole,
        address token
    ) external;
}
