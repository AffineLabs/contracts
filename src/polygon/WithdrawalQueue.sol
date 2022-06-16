// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
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
    uint256 public totalDebt;

    /// @notice Envents
    event WithdrawalQueueEnqueue(uint256 indexed pos, address indexed addr, uint256 amount);
    event WithdrawalQueueDequeue(uint256 indexed pos, address indexed addr, uint256 amount);

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
    function size() public view returns (uint256) {
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
        require(tailPtr >= headPtr, "Queue is empty");
        QueueData memory withdrawalRequest = queue[headPtr];
        delete queue[headPtr];
        totalDebt -= withdrawalRequest.amount;
        usdc.safeTransfer(withdrawalRequest.addr, withdrawalRequest.amount);
        emit WithdrawalQueueDequeue(headPtr, withdrawalRequest.addr, withdrawalRequest.amount);
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
            QueueData memory withdrawalRequest = queue[ptr];
            delete queue[ptr];
            totalDebt -= withdrawalRequest.amount;
            usdc.safeTransfer(withdrawalRequest.addr, withdrawalRequest.amount);
            emit WithdrawalQueueDequeue(ptr, withdrawalRequest.addr, withdrawalRequest.amount);
        }
        headPtr += batchSize;
    }
}
