// SPDX-License-Identifier: MIT
pragma solidity =0.8.16;

/*//////////////////////////////////////////////////////////////
                            AUDIT INFO
//////////////////////////////////////////////////////////////*/
/**
 * Audits:
 *     1. Nov 8, 2022, size: 27 Line
 * Extended: False
 */
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

library SlippageUtils {
    using FixedPointMathLib for uint256;

    uint256 constant MAX_BPS = 10_000;

    function slippageUp(uint256 amount, uint256 slippageBps) internal pure returns (uint256) {
        return amount.mulDivDown(MAX_BPS + slippageBps, MAX_BPS);
    }

    function slippageDown(uint256 amount, uint256 slippageBps) internal pure returns (uint256) {
        return amount.mulDivUp(MAX_BPS - slippageBps, MAX_BPS);
    }
}
