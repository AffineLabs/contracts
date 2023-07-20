// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IWStEth {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external returns (uint256);
}
