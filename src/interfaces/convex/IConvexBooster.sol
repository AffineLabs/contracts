// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

struct PoolInfo {
    address lptoken;
    address token;
    address gauge;
    address crvRewards;
    address stash;
    bool shutdown;
}

interface IConvexBooster {
    function poolInfo(uint256 _pid) external returns (PoolInfo memory);
    function depositAll(uint256 _pid, bool _stake) external returns (bool);
}
