// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IDelegator {
    // vault request to withdraw assets
    function requestWithdrawal(uint256 assets) external;
    // vault will check the availability of liquid assets
    function checkAssetAvailability(uint256 assets) external view returns (bool);
    // vault withdraw liquid assets call by vault
    function delegate(uint256 amount) external;
    // vault delegate assets to delegator
    function withdraw() external;
    // get delegator tvl
    function totalLockedValue() external returns (uint256);
}
