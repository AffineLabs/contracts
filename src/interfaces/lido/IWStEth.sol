// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

abstract contract IWSTETH is ERC20 {
    function unwrap(uint256 _wstETHAmount) external virtual returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external virtual returns (uint256);
}
