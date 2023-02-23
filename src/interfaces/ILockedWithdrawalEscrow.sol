// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface ILockedWithdrawalEscrow {
    function registerWithdrawalRequest(uint256 vaultShares, address user) external;
}
