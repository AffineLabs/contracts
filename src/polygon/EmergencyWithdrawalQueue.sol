// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {L2Vault} from "./L2Vault.sol";

contract EmergencyWithdrawalQueue {
    /// @notice Struct representing withdrawalRequest stored in each queue node.
    struct WithdrawalRequest {
        address owner;
        address receiver;
        uint256 shares;
        uint256 pushTime;
    }
    /// @notice Mapping representing the queue.

    mapping(uint256 => WithdrawalRequest) queue;

    /// @notice Pointer to head of the queue.
    uint256 public headPtr = 1;
    /// @notice Pointer to tail of the queue.
    uint256 public tailPtr = 0;

    /// @notice Address of Alpine vault.
    L2Vault public immutable vault;

    /// @notice Debt in shares unit.
    uint256 public shareDebt;

    // @notice User debts in share unit
    mapping(address => uint256) public debtToOwner;

    /// @notice Envents
    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos, address indexed owner, address indexed receiver, uint256 shares
    );
    event EmergencyWithdrawalQueueDequeue(
        uint256 indexed pos, address indexed owner, address indexed receiver, uint256 shares
    );

    constructor(L2Vault _vault) {
        vault = _vault;
    }

    /// @notice current size of the queue
    function size() public view returns (uint256) {
        return (tailPtr + 1) - headPtr;
    }

    /// @notice total debt
    function totalDebt() public view returns (uint256) {
        return vault.convertToAssets(shareDebt);
    }

    /// @notice enqueue user withdrawal requests to the queue.
    function enqueue(address owner, address receiver, uint256 shares) external {
        require(msg.sender == address(vault), "EWQ: only vault");
        tailPtr += 1;
        queue[tailPtr] = WithdrawalRequest(owner, receiver, shares, block.timestamp);
        shareDebt += shares;
        debtToOwner[owner] += shares;
        emit EmergencyWithdrawalQueueEnqueue(tailPtr, owner, receiver, shares);
    }

    /// @notice dequeue user withdrawal requests from the queue.
    function dequeue() external {
        require(tailPtr >= headPtr, "Queue is empty");
        WithdrawalRequest memory withdrawalRequest = queue[headPtr];
        delete queue[headPtr];
        shareDebt -= withdrawalRequest.shares;
        debtToOwner[withdrawalRequest.owner] -= withdrawalRequest.shares;
        uint256 redeemedAssetAmount = vault.redeemByEmergencyWithdrawalQueue(
            headPtr, withdrawalRequest.shares, withdrawalRequest.receiver, withdrawalRequest.owner
        );
        if (redeemedAssetAmount > 0) {
            emit EmergencyWithdrawalQueueDequeue(
                headPtr, withdrawalRequest.owner, withdrawalRequest.receiver, withdrawalRequest.shares
                );
        }
        headPtr += 1;
    }

    /// @notice dequeue user withdrawal requests from the queue in batch.
    function dequeueBatch(uint256 batchSize) external {
        require(size() >= batchSize, "Batch size too big");
        uint256 batchTailPtr = headPtr + batchSize;
        uint256 shareDebtReduction;
        for (uint256 ptr = headPtr; ptr < batchTailPtr;) {
            WithdrawalRequest memory withdrawalRequest = queue[ptr];
            delete queue[ptr];
            shareDebtReduction += withdrawalRequest.shares;
            debtToOwner[withdrawalRequest.owner] -= withdrawalRequest.shares;
            uint256 redeemedAssetAmount = vault.redeemByEmergencyWithdrawalQueue(
                ptr, withdrawalRequest.shares, withdrawalRequest.receiver, withdrawalRequest.owner
            );
            if (redeemedAssetAmount > 0) {
                emit EmergencyWithdrawalQueueDequeue(
                    headPtr, withdrawalRequest.owner, withdrawalRequest.receiver, withdrawalRequest.shares
                    );
            }
            unchecked {
                ptr++;
            }
        }
        shareDebt -= shareDebtReduction;
        headPtr += batchSize;
    }
}
