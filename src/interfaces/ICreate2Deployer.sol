// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface ICreate2Deployer {
    function deploy(uint256 value, bytes32 salt, bytes memory code) external returns (address);

    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}
