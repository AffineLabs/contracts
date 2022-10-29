// SPDX-License-Identifier: MIT
pragma solidity =0.8.16;

library Constants {
    // Message types
    // Messages received by L1
    bytes32 constant L2_FUND_TRANSFER_REPORT = keccak256("L2_FUND_TRANSFER_REPORT");
    bytes32 constant L2_FUND_REQUEST = keccak256("L2_FUND_REQUEST");

    // Messages received by L2
    bytes32 constant L1_TVL = keccak256("L1_TVL");
    bytes32 constant L1_FUND_TRANSFER_REPORT = keccak256("L1_FUND_TRANSFER_REPORT");
}
