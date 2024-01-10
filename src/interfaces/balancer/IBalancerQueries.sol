// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IBalancerVault} from "./IBalancerVault.sol";

interface IBalancerQueries {
    function querySwap(IBalancerVault.SingleSwap memory singleSwap, IBalancerVault.FundManagement memory funds)
        external
        returns (uint256);
}
