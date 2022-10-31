// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {CREATE3} from "solmate/src/utils/CREATE3.sol";

contract Create3Deployer {
    function deploy(bytes32 salt, bytes memory creationCode, uint256 value) external returns (address deployed) {
        deployed = CREATE3.deploy(salt, creationCode, value);
    }

    function getDeployed(bytes32 salt) external view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}
