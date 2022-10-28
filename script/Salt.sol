// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";

abstract contract Salt is Script {
    function _getSalt() internal returns (bytes32 salt) {
        string[] memory inputs = new string[](4);
        inputs[0] = "yarn";
        inputs[1] = "--silent";
        inputs[2] = "ts-node";
        inputs[3] = "scripts/utils/get-bytes.ts";
        bytes memory res = vm.ffi(inputs);
        salt = keccak256(res);
    }
}
