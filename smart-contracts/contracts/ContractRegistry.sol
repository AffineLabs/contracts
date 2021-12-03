// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ContractRegistry is Ownable {
    mapping(string => address) private registry;

    function addOrUpdateAddress(string calldata contractName, address contractAddress) external {
        registry[contractName] = contractAddress;
    }

    function getAddress(string calldata contractName) external view returns(address) {
        require(registry[contractName] != address(0), string(abi.encodePacked(contractName, ": Contract not found in the registry")));
        return registry[contractName];
    }
}