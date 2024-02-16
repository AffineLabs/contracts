// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/*//////////////////////////////////////////////////////////////
                            AUDIT INFO
//////////////////////////////////////////////////////////////*/
/**
 * Audits:
 *     1. Nov 8, 2022, size: 18 Line
 * Extended: False
 */

/*  solhint-disable func-visibility */
function uncheckedInc(uint256 i) pure returns (uint256) {
    unchecked {
        return i + 1;
    }
}
