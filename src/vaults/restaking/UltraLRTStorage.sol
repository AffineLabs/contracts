// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

abstract contract UltraLRTStorage {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    // Token approval
    bytes32 public constant APPROVED_TOKEN = keccak256("APPROVED_TOKEN");
}
