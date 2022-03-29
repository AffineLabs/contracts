// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface IL1Vault {
    function afterReceive() external;
}

interface IL2Vault {
    function afterReceive(uint256 amount) external;
}
