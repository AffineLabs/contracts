// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

library Constants {
    bytes32 constant NORMAL_REBALANCE = keccak256("NORMAL_REBALANCE");
    bytes32 constant EMERGENCY_REBALANCE = keccak256("EMERGENCY_REBALANCE");
}