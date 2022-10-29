// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

type Dollar is uint256;

library DollarMath {
    function add(Dollar a, Dollar b) internal pure returns (Dollar) {
        return Dollar.wrap(Dollar.unwrap(a) + Dollar.unwrap(b));
    }

    function sub(Dollar a, Dollar b) internal pure returns (Dollar) {
        return Dollar.wrap(Dollar.unwrap(a) - Dollar.unwrap(b));
    }

    function mul(Dollar a, Dollar b) internal pure returns (Dollar) {
        return Dollar.wrap(Dollar.unwrap(a) * Dollar.unwrap(b));
    }

    function div(Dollar a, Dollar b) internal pure returns (Dollar) {
        return Dollar.wrap(Dollar.unwrap(a) / Dollar.unwrap(b));
    }
}
