// SPDX-License-Identifier: BUSL-1.1
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
