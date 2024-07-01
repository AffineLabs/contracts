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
    function queueWithdrawals(QueuedWithdrawalParams[] calldata) external returns (bytes32[] memory);
    function completeQueuedWithdrawals(
        WithdrawalInfo[] calldata,
        address[][] calldata,
        uint256[] calldata,
        bool[] calldata
    ) external;
    function calculateWithdrawalRoot(WithdrawalInfo memory withdrawal) external pure returns (bytes32);
    function pendingWithdrawals(bytes32) external view returns (bool);
    /**
     * @notice returns the address of the operator that `staker` is delegated to.
     * @notice Mapping: staker => operator whom the staker is currently delegated to.
     * @dev Note that returning address(0) indicates that the staker is not actively delegated to any operator.
     */
    function delegatedTo(address staker) external view returns (address);
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
