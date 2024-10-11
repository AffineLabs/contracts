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
    error ExceedsDepositLimit();
    error ExceedsMintLimit();
    error ExceedsWithdrawLimit();
    error ExceedsRedeemLimit();
    error InsufficientLiquidAssets();
    error ExistingEscrowDebt();
    error InvalidEscrowVault();
    error ExceedsDelegatorWithdrawableAssets();
    error ExceedsMaxDelegatorLimit();
    error NonZeroEmptyDelegatorTVL();
    error InactiveDelegator();
    error RequireHarvest();
    error ProfitUnlocking();
    error DepositPaused();
    error InvalidDelegatorFactory();
    error RunningEpoch();
    error NoResolvingEpoch();
    error MaxUnresolvedEpochReached();
    error InvalidEscrow();
    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken();
    error InvalidFeeBps();
    error MaxLimitReached();
    error AssetExists();
    error NonZeroTVL();
    error AssetPaused();
    error InvalidDataLength();
    error InsufficientAssets();
}
