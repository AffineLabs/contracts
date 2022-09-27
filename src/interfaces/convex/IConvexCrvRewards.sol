// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface IConvexCrvRewards {
    function withdrawAllAndUnwrap(bool claim) external returns(bool);
}