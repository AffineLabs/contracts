// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract WithdrawalQueue is AccessControl {
    using SafeTransferLib for ERC20;

    /// @notice Struct representing withdrawalRequest stored in each queue node.
    struct QueueData {
        address addr;
        uint256 amount;
        uint256 pushTime;
    }
    /// @notice Mapping representing the queue.
    mapping(uint256 => QueueData) queue;

    /// @notice Pointer to head of the queue.
    uint256 headPtr = 1;
    /// @notice Pointer to tail of the queue.
    uint256 tailPtr = 0;

    /// @notice Admin role.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    /// @notice Governance role.
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE");
    /// @notice Address of Alpine vault.
    address public vault;
    /// @notice Address of USDC token.
    ERC20 public usdc;

    /// @notice Total debt.
    uint256 totalDebt;

    /// @notice Envents
    event WithdrawalQueueEnqueue(uint256 pos, address addr, uint256 amount);
    event WithdrawalQueueDequeue(uint256 pos, address addr, uint256 amount);

    constructor(
        address _vault,
        address _governance,
        ERC20 _usdc
    ) {
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, GOVERNANCE_ROLE);

        _setupRole(GOVERNANCE_ROLE, _governance);
        _setupRole(OPERATOR_ROLE, _vault);

        usdc = _usdc;
    }

    /// @notice current size of the queue
    function size() external view returns (uint256) {
        return (tailPtr + 1) - headPtr;
    }

    /// @notice enqueue user withdrawal requests to the queue.
    function enqueue(address addr, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        tailPtr += 1;
        queue[tailPtr] = QueueData(addr, amount, block.timestamp);
        totalDebt += amount;
        emit WithdrawalQueueEnqueue(tailPtr, addr, amount);
    }

    /// @notice dequeue user withdrawal requests from the queue.
    function dequeue() external {
        require(tailPtr >= headPtr); // non-empty queue
        QueueData memory withdrawalRequest = queue[headPtr];
        delete queue[headPtr];
        headPtr += 1;
        totalDebt -= withdrawalRequest.amount;
        usdc.safeTransfer(withdrawalRequest.addr, withdrawalRequest.amount);
        emit WithdrawalQueueDequeue(tailPtr, withdrawalRequest.addr, withdrawalRequest.amount);
    }

    /// @notice dequeue user withdrawal requests from the queue in batch.
    function dequeueBatch(uint256 batchSize) external {
        require(this.size() >= batchSize);
        for (uint256 ptr = headPtr; ptr < headPtr + batchSize; ptr++) {
            QueueData memory withdrawalRequest = queue[ptr];
            delete queue[ptr];
            totalDebt -= withdrawalRequest.amount;
            usdc.safeTransfer(withdrawalRequest.addr, withdrawalRequest.amount);
            emit WithdrawalQueueDequeue(tailPtr, withdrawalRequest.addr, withdrawalRequest.amount);
        }
        headPtr += batchSize;
    }
}
