// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Router} from "./ERC4626Router.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

// TODO: Fix this in constructor
/*  solhint-disable reason-string, no-unused-vars */

contract Router is ERC4626Router {
    constructor(string memory name, address forwarder, IWETH _weth) ERC4626Router(name) {
        weth = _weth;
    }

    IWETH public immutable weth;

    function depositNative() external payable {
        weth.deposit{value: msg.value}();
    }
}
