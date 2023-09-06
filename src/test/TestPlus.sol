// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Deploy} from "./Deploy.sol";

contract TestPlus is Test, Deploy {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    uint256 constant ETH_FORK_BLOCK = 16_897_451;
    uint256 constant POLYGON_FORK_BLOCK = 38_961_333;

    function forkEth() internal {
        vm.createSelectFork("ethereum", ETH_FORK_BLOCK);
    }

    function forkPolygon() internal {
        vm.createSelectFork("polygon", POLYGON_FORK_BLOCK);
    }

    function forkArb() internal {
        vm.createSelectFork("arbitrum", 124_531_545);
    }

    function forkBase() internal {
        vm.createSelectFork("base", 3_584_744);
    }

    function assertInRange(uint256 a, uint256 b1, uint256 b2) internal {
        if (a < b1 || a > b2) {
            emit log("Error: a in range [b1, b2] not satisfied [uint]");
            emit log_named_uint("Expected b1", b1);
            emit log_named_uint("Expected b2", b2);
            emit log_named_uint("     Actual", a);
            fail();
        }
    }
}
