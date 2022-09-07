// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {L2Vault} from "./L2Vault.sol";

contract EmergencyWithdrawalQueue is AccessControl {
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

    /// @notice Queue Admin role.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    /// @notice Address of Alpine vault.
    L2Vault public vault;

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

    constructor(address _governance) {
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
    }

    function linkVault(L2Vault _vault) public {
        // This will give the governance ability to link vault. Others won't
        // be able to re-link vaults once it is set.
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            require(address(vault) == address(0), "Vault is already linked");
        }
        require(_vault.emergencyWithdrawalQueue() == this);
        _grantRole(OPERATOR_ROLE, address(_vault));
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
    function enqueue(address owner, address receiver, uint256 shares) external onlyRole(OPERATOR_ROLE) {
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
