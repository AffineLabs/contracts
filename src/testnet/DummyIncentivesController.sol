// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract DummyIncentivesController {
    constructor() {}

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external pure returns (uint256) {
        assets;
        amount;
        to;
        return 0;
    }

    function getRewardsBalance(address[] calldata assets, address user) external pure returns (uint256) {
        assets;
        user;
        return 0;
    }
}
