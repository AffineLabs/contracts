// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

struct WithdrawalInfo {
    address staker;
    address delegatedTo;
    address withdrawer;
    uint256 nonce;
    uint32 startBlock;
    address[] strategies;
    uint256[] shares;
}

struct QueuedWithdrawalParams {
    address[] strategies;
    uint256[] shares;
    address recipient;
}

struct ApproverSignatureAndExpiryParams {
    bytes signature;
    uint256 expiry;
}

interface IDelegationManager {
    function delegateTo(address, ApproverSignatureAndExpiryParams calldata, bytes32) external;
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external;
    function completeQueuedWithdrawals(
        WithdrawalInfo[] calldata,
        address[][] calldata,
        uint256[] calldata,
        bool[] calldata
    ) external;
}

interface IStrategyManager {
    function depositIntoStrategy(address, address, uint256) external;
}

interface IStrategy {
    function underlyingToShares(uint256) external view returns (uint256);
    function sharesToUnderlying(uint256) external view returns (uint256);
    function userUnderlyingView(address) external view returns (uint256);
    function sharesToUnderlyingView(uint256) external view returns (uint256);
    function shares(address) external view returns (uint256);
}
