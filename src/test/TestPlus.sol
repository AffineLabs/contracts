// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

contract TestPlus is Test {
    using stdStorage for StdStorage;

    function assertInRange(
        uint256 a,
        uint256 b1,
        uint256 b2
    ) internal {
        if (a < b1 || a > b2) {
            emit log("Error: a in range [b1, b2] not satisfied [uint]");
            emit log_named_uint("Expected b1", b1);
            emit log_named_uint("Expected b2", b2);
            emit log_named_uint("     Actual", a);
            fail();
        }
    }

    function mkaddr(string memory name) internal returns (address) {
        address addr = address(uint160(uint256(keccak256(abi.encodePacked(name)))));
        vm.label(addr, name);
        return addr;
    }
}
