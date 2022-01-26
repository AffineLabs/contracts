// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IHevm {
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;

    function warp(uint256 x) external;

    function startPrank(address sender) external;

    function stopPrank() external;
}
