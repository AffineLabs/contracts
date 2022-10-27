// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

function uncheckedInc(uint256 i) pure returns (uint256) {
    unchecked {
        return i + 1;
    }
}
