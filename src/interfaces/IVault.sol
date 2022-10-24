// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

interface IL1Vault {
    function afterReceive() external;
    function governance() external view returns (address);
}

interface IL2Vault {
    function afterReceive(uint256 amount) external;
}
