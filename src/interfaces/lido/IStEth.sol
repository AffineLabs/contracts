// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;
interface IStEth {
    function submit(address _referral) external payable returns (uint256);
}