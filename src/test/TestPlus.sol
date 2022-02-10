// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DSTest } from "./test.sol";

contract DSTestPlus is DSTest {
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
