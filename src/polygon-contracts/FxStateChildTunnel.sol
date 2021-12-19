// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { FxBaseChildTunnel } from "../tunnel/FxBaseChildTunnel.sol";

interface IContractRegistry {
    function getAddress(string calldata contractName) external view returns (address);
}

/**
 * @title FxStateChildTunnel
 */
contract FxStateChildTunnel is FxBaseChildTunnel {
    uint256 public latestStateId;
    address public latestRootMessageSender;
    bytes public latestData;
    // Address of L2 contarct registry.
    IContractRegistry public l2ContractRegistry;

    constructor(address _fxChild, address _l2ContractRegistryAddress) FxBaseChildTunnel(_fxChild) {
        l2ContractRegistry = IContractRegistry(_l2ContractRegistryAddress);
    }

    function _processMessageFromRoot(
        uint256 stateId,
        address sender,
        bytes memory data
    ) internal override validateSender(sender) {
        latestStateId = stateId;
        latestRootMessageSender = sender;
        latestData = data;
    }

    function sendMessageToRoot(bytes memory message) public {
        require(msg.sender == l2ContractRegistry.getAddress("L2Vault"), "Only L2Vault can send data to L1.");
        _sendMessageToRoot(message);
    }
}
