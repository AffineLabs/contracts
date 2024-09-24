// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IPriceFeed {
    function getPrice() external view returns (uint256 rate, uint256 timestamp);
}
