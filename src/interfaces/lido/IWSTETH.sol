// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

abstract contract IWSTETH is ERC20 {
    function unwrap(uint256 _wstETHAmount) external virtual returns (uint256);
    function wrap(uint256 _stETHAmount) external virtual returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view virtual returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view virtual returns (uint256);
    function stEthPerToken() external view virtual returns (uint256);
    function tokensPerStEth() external view virtual returns (uint256);
}
