// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IDelegator {
    // vault request to withdraw assets
    function requestWithdrawal(uint256 assets) external returns (uint256);
    // harvester sends assets to vault to resolve debt from vault
    function completeWithdrawalRequest() external;
    // vault will check the availability of liquid assets
    function checkAssetAvailability(uint256 assets) external view returns (bool);
    // vault withdraw liquid assets call by vault
    function withdraw(uint256 assets) external returns (uint256);
    // vault delegate assets to delegator
    function delegate(uint256 assets) external;
    // get delegator tvl
    function tvl() external returns (uint256);
}
