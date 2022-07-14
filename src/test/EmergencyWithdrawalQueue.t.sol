// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ConvertLib } from "./ConvertLib.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { EmergencyWithdrawalQueue } from "../polygon/emergencyWithdrawalQueue.sol";

contract EmergencyWithdrawalQueueTest is TestPlus {
    EmergencyWithdrawalQueue emergencyWithdrawalQueue;
    MockERC20 usdc;

    L2Vault vault = Deploy.deployL2Vault();
    address governance = address(uint160(uint256(keccak256("GOVERNANCE"))));

    address user1 = address(uint160(block.timestamp));
    address user2 = address(uint160(block.timestamp + 1));

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        EmergencyWithdrawalQueue.RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );
    event EmergencyWithdrawalQueueDequeue(
        uint256 indexed pos,
        EmergencyWithdrawalQueue.RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    function setUp() public {
        usdc = new MockERC20("Test USDC", "USDC", 6);
        emergencyWithdrawalQueue = new EmergencyWithdrawalQueue(vault, governance, usdc);
        usdc.mint(address(emergencyWithdrawalQueue), 10000);
    }

    function testEnqueueSuccess() external {
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, EmergencyWithdrawalQueue.RequestType.Withdraw, user2, user1, 1000);
        // Impersonate vault
        vm.startPrank(address(vault));
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        vm.stopPrank();

        assertEq(emergencyWithdrawalQueue.size(), 1);
    }

    function testEnqueueOnlyVaultCanEnqueue() external {
        vm.expectRevert(
            bytes(
                abi.encodePacked(
                    "AccessControl: account ",
                    ConvertLib.toString(address(this)),
                    " is missing role ",
                    ConvertLib.toString(keccak256("OPERATOR"))
                )
            )
        );
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);
    }

    function testEnqueueCorreclyEnqueuReturningUser() external {
        // Impersonate vault
        vm.startPrank(address(vault));

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, EmergencyWithdrawalQueue.RequestType.Withdraw, user2, user1, 1000);
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(2, EmergencyWithdrawalQueue.RequestType.Withdraw, user1, user2, 2000);
        emergencyWithdrawalQueue.enqueue(user1, user2, 2000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(3, EmergencyWithdrawalQueue.RequestType.Withdraw, user2, user1, 3000);
        emergencyWithdrawalQueue.enqueue(user2, user1, 3000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.stopPrank();

        assertEq(emergencyWithdrawalQueue.size(), 3);
    }

    function testDequeueSuccess() external {
        // Impersonate vault
        vm.startPrank(address(vault));
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        emergencyWithdrawalQueue.enqueue(user1, user2, 2000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        emergencyWithdrawalQueue.enqueue(user2, user1, 3000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.stopPrank();

        vm.expectEmit(false, false, false, false);
        emit Transfer(address(emergencyWithdrawalQueue), user1, 1000);
        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(1, EmergencyWithdrawalQueue.RequestType.Withdraw, user2, user1, 1000);
        emergencyWithdrawalQueue.dequeue();
        assertEq(emergencyWithdrawalQueue.size(), 2);

        vm.expectEmit(false, false, false, false);
        emit Transfer(address(emergencyWithdrawalQueue), user2, 2000);
        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(2, EmergencyWithdrawalQueue.RequestType.Withdraw, user1, user2, 2000);
        vm.expectEmit(false, false, false, false);
        emit Transfer(address(emergencyWithdrawalQueue), user1, 3000);
        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(3, EmergencyWithdrawalQueue.RequestType.Withdraw, user2, user1, 3000);
        emergencyWithdrawalQueue.dequeueBatch(2);
        assertEq(emergencyWithdrawalQueue.size(), 0);
    }
}
