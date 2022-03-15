// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";

import { IHevm } from "./IHevm.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { WithdrawalQueue } from "../polygon/WithdrawalQueue.sol";
import { ConvertLib } from "./ConvertLib.sol";

contract WithdrawalQueueTest is DSTest {
    WithdrawalQueue withdrawalQueue;
    MockERC20 usdc;

    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address vault = address(uint160(uint256(keccak256("VAULT"))));
    address governance = address(uint160(uint256(keccak256("GOVERNANCE"))));

    address user1 = address(uint160(block.timestamp));
    address user2 = address(uint160(block.timestamp + 1));

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event WithdrawalQueueEnqueue(uint256 indexed pos, address indexed addr, uint256 amount);
    event WithdrawalQueueDequeue(uint256 indexed pos, address indexed addr, uint256 amount);

    function setUp() public {
        usdc = new MockERC20("Test USDC", "USDC", 6);
        withdrawalQueue = new WithdrawalQueue(vault, governance, usdc);
        usdc.mint(address(withdrawalQueue), 10000);
    }

    function testEnqueueSuccess() external {
        hevm.expectEmit(true, true, false, true);
        emit WithdrawalQueueEnqueue(1, user1, 1000);
        // Impersonate vault
        hevm.startPrank(vault);
        // Only vault should be able to enqueue.
        withdrawalQueue.enqueue(user1, 1000);
        hevm.stopPrank();

        assertEq(withdrawalQueue.size(), 1);
    }

    function testEnqueueOnlyVaultCanEnqueue() external {
        hevm.expectRevert(
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
        withdrawalQueue.enqueue(user1, 1000);
    }

    function testEnqueueCorreclyEnqueuReturningUser() external {
        // Impersonate vault
        hevm.startPrank(vault);

        hevm.expectEmit(true, true, false, true);
        emit WithdrawalQueueEnqueue(1, user1, 1000);
        withdrawalQueue.enqueue(user1, 1000);

        hevm.expectEmit(true, true, false, true);
        emit WithdrawalQueueEnqueue(2, user2, 2000);
        withdrawalQueue.enqueue(user2, 2000);

        hevm.expectEmit(true, true, false, true);
        emit WithdrawalQueueEnqueue(3, user1, 3000);
        withdrawalQueue.enqueue(user1, 3000);

        hevm.stopPrank();

        assertEq(withdrawalQueue.size(), 3);
    }

    function testDequeueSuccess() external {
        // Impersonate vault
        hevm.startPrank(vault);
        // Only vault should be able to enqueue.
        withdrawalQueue.enqueue(user1, 1000);
        withdrawalQueue.enqueue(user2, 2000);
        withdrawalQueue.enqueue(user1, 3000);
        hevm.stopPrank();

        hevm.expectEmit(false, false, false, false);
        emit Transfer(address(withdrawalQueue), user1, 1000);
        hevm.expectEmit(false, false, false, false);
        emit WithdrawalQueueDequeue(1, user1, 1000);
        withdrawalQueue.dequeue();
        assertEq(withdrawalQueue.size(), 2);

        hevm.expectEmit(false, false, false, false);
        emit Transfer(address(withdrawalQueue), user2, 2000);
        hevm.expectEmit(false, false, false, false);
        emit WithdrawalQueueDequeue(2, user2, 2000);
        hevm.expectEmit(false, false, false, false);
        emit Transfer(address(withdrawalQueue), user1, 3000);
        hevm.expectEmit(false, false, false, false);
        emit WithdrawalQueueDequeue(3, user2, 3000);
        withdrawalQueue.dequeueBatch(2);
        assertEq(withdrawalQueue.size(), 0);
    }
}