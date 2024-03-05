// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

library ReStakingErrors {
    error AlreadyApprovedToken();
    error NotApprovedToken();
    error DepositAmountCannotBeZero();
    error CannotDepositForZeroAddress();
    error TokenNotAllowedForStaking();
    error WithdrawAmountCannotBeZero();
    error InvalidWithdrawalAmount();
}
