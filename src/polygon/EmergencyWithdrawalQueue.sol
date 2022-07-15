// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { L2Vault } from "./L2Vault.sol";

contract EmergencyWithdrawalQueue is AccessControl {
    using SafeTransferLib for ERC20;

    /// @notice Enum representing type of withdrawal requests.
    /// See {IERC4626-redeem} and {IERC4626-withdraw}
    enum RequestType {
        Withdraw,
        Redeem
    }
    /// @notice Struct representing withdrawalRequest stored in each queue node.
    struct WithdrawalRequest {
        RequestType requestType;
        address owner;
        address receiver;
        uint256 amount;
        uint256 pushTime;
    }
    /// @notice Mapping representing the queue.
    mapping(uint256 => WithdrawalRequest) queue;

    /// @notice Pointer to head of the queue.
    uint256 headPtr = 1;
    /// @notice Pointer to tail of the queue.
    uint256 tailPtr = 0;

    /// @notice Admin role.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    /// @notice Governance role.
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE");
    /// @notice Address of Alpine vault.
    L2Vault public vault;
    /// @notice Address of USDC token.
    ERC20 public usdc;

    /// @notice Debt in shares from redeem requests
    uint256 public shareDebt;
    /// @notice Debt in assets from withdraw requests
    uint256 public assetDebt;

    /// @notice Envents
    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );
    event EmergencyWithdrawalQueueDequeue(
        uint256 indexed pos,
        RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    constructor(
        L2Vault _vault,
        address _governance,
        ERC20 _usdc
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(OPERATOR_ROLE, address(_vault));

        vault = _vault;
        usdc = _usdc;
    }

    /// @notice current size of the queue
    function size() public view returns (uint256) {
        return (tailPtr + 1) - headPtr;
    }

    /// @notice total debt
    function totalDebt() public view returns (uint256) {
        return assetDebt + vault.convertToAssets(shareDebt);
    }

    /// @notice enqueue user withdrawal requests to the queue.
    function enqueue(
        address owner,
        address receiver,
        uint256 amount,
        RequestType requestType
    ) external onlyRole(OPERATOR_ROLE) {
        tailPtr += 1;
        queue[tailPtr] = WithdrawalRequest(requestType, owner, receiver, amount, block.timestamp);
        if (requestType == RequestType.Withdraw) {
            assetDebt += amount;
        }
        if (requestType == RequestType.Redeem) {
            shareDebt += amount;
        }
        emit EmergencyWithdrawalQueueEnqueue(tailPtr, requestType, owner, receiver, amount);
    }

    /// @notice dequeue user withdrawal requests from the queue.
    function dequeue() external {
        require(tailPtr >= headPtr, "Queue is empty");
        WithdrawalRequest memory withdrawalRequest = queue[headPtr];
        delete queue[headPtr];
        if (withdrawalRequest.requestType == RequestType.Withdraw) {
            vault.withdraw(withdrawalRequest.amount, withdrawalRequest.receiver, withdrawalRequest.owner);
            assetDebt -= withdrawalRequest.amount;
        }
        if (withdrawalRequest.requestType == RequestType.Redeem) {
            vault.redeem(withdrawalRequest.amount, withdrawalRequest.receiver, withdrawalRequest.owner);
            shareDebt -= withdrawalRequest.amount;
        }
        emit EmergencyWithdrawalQueueDequeue(
            headPtr,
            withdrawalRequest.requestType,
            withdrawalRequest.owner,
            withdrawalRequest.receiver,
            withdrawalRequest.amount
        );
        headPtr += 1;
    }

    function unchecked_inc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    /// @notice dequeue user withdrawal requests from the queue in batch.
    function dequeueBatch(uint256 batchSize) external {
        require(size() >= batchSize, "Batch size too big");
        uint256 batchTailPtr = headPtr + batchSize;
        for (uint256 ptr = headPtr; ptr < batchTailPtr; ptr = unchecked_inc(ptr)) {
            WithdrawalRequest memory withdrawalRequest = queue[ptr];
            delete queue[ptr];
            if (withdrawalRequest.requestType == RequestType.Withdraw) {
                vault.withdraw(withdrawalRequest.amount, withdrawalRequest.receiver, withdrawalRequest.owner);
                assetDebt -= withdrawalRequest.amount;
            }
            if (withdrawalRequest.requestType == RequestType.Redeem) {
                vault.redeem(withdrawalRequest.amount, withdrawalRequest.receiver, withdrawalRequest.owner);
                shareDebt -= withdrawalRequest.amount;
            }
            emit EmergencyWithdrawalQueueDequeue(
                headPtr,
                withdrawalRequest.requestType,
                withdrawalRequest.owner,
                withdrawalRequest.receiver,
                withdrawalRequest.amount
            );
        }
        headPtr += batchSize;
    }
}
