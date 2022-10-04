// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

// See https://etherscan.io/address/0xDd49A93FDcae579AE50B4b9923325e9e335ec82B#code
interface IConvexClaimZap {
    function crv() external view returns (address);
    function cvx() external view returns (address);
    function claimRewards(
        address[] calldata rewardContracts,
        address[] calldata extraRewardContracts,
        address[] calldata tokenRewardContracts,
        address[] calldata tokenRewardTokens,
        uint256 depositCrvMaxAmount,
        uint256 minAmountOut,
        uint256 depositCvxMaxAmount,
        uint256 spendCvxAmount,
        uint256 options
    ) external;
}
