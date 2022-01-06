// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

interface ICreate2Deployer {
    function deploy(
        uint256 value,
        bytes32 salt,
        bytes memory code
    ) external returns (address);
}
