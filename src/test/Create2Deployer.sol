// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";

contract Create2Deployer is ICreate2Deployer {
    constructor() {}

    function deploy(
        uint256 value,
        bytes32 salt,
        bytes memory code
    ) external returns (address) {
        return Create2.deploy(value, salt, code);
    }

    function computeAddress(bytes32 salt, bytes32 codeHash) public view returns (address) {
        return Create2.computeAddress(salt, codeHash);
    }
}
