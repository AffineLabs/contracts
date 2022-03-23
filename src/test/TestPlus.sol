// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DSTest } from "./test.sol";
import { CheatCodes } from "./CheatCodes.sol";
import "forge-std/src/stdlib.sol";

contract DSTestPlus is DSTest {
    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    StdStorage stdstore;

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
}
