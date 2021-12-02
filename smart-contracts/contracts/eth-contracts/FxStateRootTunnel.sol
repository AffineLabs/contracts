// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import { FxBaseRootTunnel } from "../tunnel/FxBaseRootTunnel.sol";
import { BytesLib } from "../library/BytesLib.sol";

interface IContractRegistry {
    function getAddress(string calldata contractName) external view returns(address);
}

interface IL1Vault {
    function addDebtToL2(uint256 amount) external;
}

/**
 * @title FxStateRootTunnel
 */
contract FxStateRootTunnel is FxBaseRootTunnel {
    using BytesLib for bytes;
    bytes public latestData;
    IContractRegistry private l1ContractRegistry;

    constructor(address _checkpointManager, address _fxRoot, address _l1ContractRegistryAddress) 
        FxBaseRootTunnel(_checkpointManager, _fxRoot) {
        l1ContractRegistry = IContractRegistry(_l1ContractRegistryAddress);
    }

    function _processMessageFromChild(bytes memory data) internal override {
        require(msg.sender == l1ContractRegistry.getAddress("Defender"), "FxStateRootTunnel[_processMessageFromChild]: Only defender should be able to present proof for L2 Vault Message.");
        latestData = data;
        (uint256 amount) = abi.decode(data, (uint256));
        IL1Vault(l1ContractRegistry.getAddress("L1Vault")).addDebtToL2(amount);
    }

    function sendMessageToChild(bytes memory message) public {
        _sendMessageToChild(message);
    }
}
