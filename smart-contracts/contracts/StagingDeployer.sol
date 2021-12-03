//SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Staging } from "./Staging.sol";

contract StagingDeployer {
    address deployAddress;

    constructor(
        address _l1ContractRegistryAddress,
        address _l2ContractRegistryAddress,
        uint24 _rootChainId,
        uint24 _childChainId,
        bytes32 _salt
    ) {
        bytes memory bytecode = abi.encodePacked(
            type(Staging).creationCode,
            abi.encode(
                _l1ContractRegistryAddress, 
                _l2ContractRegistryAddress, 
                _rootChainId, 
                _childChainId
            )
        );
        deployAddress = Create2.deploy(0, _salt, bytecode);
    }

    function getDeployedAddress() external view returns (address) {
        return deployAddress;
    }
}