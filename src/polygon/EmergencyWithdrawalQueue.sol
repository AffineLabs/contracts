// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {L2Vault} from "./L2Vault.sol";
import {uncheckedInc} from "../libs/Unchecked.sol";

contract EmergencyWithdrawalQueue {
    /// @notice Address of Alpine vault.
    L2Vault public immutable vault;

    constructor(L2Vault _vault) {
        vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                              QUEUE STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct representing withdrawalRequest stored in each queue node.
    struct WithdrawalRequest {
        address owner;
        address receiver;
        uint256 shares;
        uint256 pushTime;
    }
    /// @notice Mapping representing the queue.

    mapping(uint256 => WithdrawalRequest) queue;

    /**
     * @dev The tailPtr is to the right of the headPtr on a number line
     * We start with tail(0) -> head(1)
     * After an enqueue we have tail(1) == head(1)
     */
    /// @notice Pointer to head of the queue.
    uint128 public headPtr = 1;
    /// @notice Pointer to tail of the queue.
    uint128 public tailPtr = 0;

    /// @notice current size of the queue
    function size() public view returns (uint256) {
        return (tailPtr + 1) - headPtr;
    }

    /*//////////////////////////////////////////////////////////////
                                  DEBT
    //////////////////////////////////////////////////////////////*/

    /// @notice Debt in shares unit.
    uint256 public shareDebt;

    /// @notice Total debt
    function totalDebt() public view returns (uint256) {
        return vault.convertToAssets(shareDebt);
    }

    // @notice User debts in share unit
    mapping(address => uint256) public ownerToDebt;

    /*//////////////////////////////////////////////////////////////
                                PUSH/POP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when we push onto the queue.
     * @param pos The users position in the queue.
     * @param owner The owner of the shares.
     * @param receiver The user who will receive the assets during share redemption
     * @param shares The number of shares to redeem.
     */
    event Push(uint256 indexed pos, address indexed owner, address indexed receiver, uint256 shares);
    /// @notice Emitted when we pop a request from the queue. See `Push` for the parameter info
    /// @dev This is only emitted when we successfully burn the user's shares. Invalid requests are skipped.
    event Pop(uint256 indexed pos, address indexed owner, address indexed receiver, uint256 shares);

    /// @notice Enqueue user withdrawal requests to the queue.
    function enqueue(address owner, address receiver, uint256 shares) external {
        require(msg.sender == address(vault), "EWQ: only vault");
        tailPtr += 1;
        queue[tailPtr] = WithdrawalRequest(owner, receiver, shares, block.timestamp);
        shareDebt += shares;
        ownerToDebt[owner] += shares;
        emit Push(tailPtr, owner, receiver, shares);
    }

    /// @notice Dequeue user withdrawal requests.
    function dequeue() external {
        require(tailPtr >= headPtr, "EWQ: queue is empty");
        WithdrawalRequest memory withdrawalRequest = queue[headPtr];
        delete queue[headPtr];
        shareDebt -= withdrawalRequest.shares;
        ownerToDebt[withdrawalRequest.owner] -= withdrawalRequest.shares;

        try vault.redeem(withdrawalRequest.shares, withdrawalRequest.receiver, withdrawalRequest.owner) {
            emit Pop(headPtr, withdrawalRequest.owner, withdrawalRequest.receiver, withdrawalRequest.shares);
            headPtr += 1;
        } catch Error(string memory reason) {
            if (keccak256(bytes(reason)) == keccak256("L2Vault: bad dequeue")) {
                // Do nothing while we wait for the vault to get enough assets
                revert("Ewq: assets pending");
            } else {
                // The request is invalid for some reason
                // (e.g. the user has a lower balance than they did when making request)
                headPtr += 1;
            }
        }
    }

    /// @notice Dequeue user withdrawal requests in a batch.
    function dequeueBatch(uint256 batchSize) external {
        require(size() >= batchSize, "EWQ: batch too big");

        uint256 batchTailPtr = headPtr + batchSize;
        uint256 shareDebtReduction;

        for (uint256 ptr = headPtr; ptr < batchTailPtr; ptr = uncheckedInc(ptr)) {
            WithdrawalRequest memory withdrawalRequest = queue[ptr];
            delete queue[ptr];
            shareDebtReduction += withdrawalRequest.shares;
            ownerToDebt[withdrawalRequest.owner] -= withdrawalRequest.shares;

            try vault.redeem(withdrawalRequest.shares, withdrawalRequest.receiver, withdrawalRequest.owner) {
                emit Pop(ptr, withdrawalRequest.owner, withdrawalRequest.receiver, withdrawalRequest.shares);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == keccak256("L2Vault: bad dequeue")) {
                    // Not enough assets
                    revert("Ewq: assets pending");
                } else {
                    // The request is invalid for some reason
                    // (e.g. the user has a lower balance than they did when making request)
                }
            }
        }
        shareDebt -= shareDebtReduction;
        headPtr += uint128(batchSize);
    }
}
