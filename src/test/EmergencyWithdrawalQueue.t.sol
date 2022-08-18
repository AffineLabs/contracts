// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { ConvertLib } from "./ConvertLib.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { EmergencyWithdrawalQueue } from "../polygon/EmergencyWithdrawalQueue.sol";

contract EmergencyWithdrawalQueueTest is TestPlus {
    using stdStorage for StdStorage;

    MockERC20 usdc;
    EmergencyWithdrawalQueue emergencyWithdrawalQueue;
    L2Vault vault;

    address user1 = address(uint160(block.timestamp + 1));
    address user2 = address(uint160(block.timestamp + 2));

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );
    event EmergencyWithdrawalQueueDequeue(
        uint256 indexed pos,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    function setUp() public {
        vault = Deploy.deployL2Vault();
        usdc = new MockERC20("Test USDC", "USDC", 6);
        usdc.mint(address(emergencyWithdrawalQueue), 10000);
        emergencyWithdrawalQueue = vault.emergencyWithdrawalQueue();
    }

    function testOnlyGovernanceCanReLinkVault() external {
        vm.startPrank(vault.governance());
        // Governance can link vault.
        emergencyWithdrawalQueue.linkVault(vault);

        changePrank(user1);
        // Anyone other than governance trying to re-link should throw error.
        vm.expectRevert(bytes("Vault is already linked"));
        emergencyWithdrawalQueue.linkVault(vault);
    }

    function testEnqueueSuccess() external {
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user2, user1, 1000);
        // Impersonate vault
        vm.startPrank(address(vault));
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        vm.stopPrank();

        assertEq(emergencyWithdrawalQueue.size(), 1);
    }

    function testEnqueueSuccessWithRedeem() external {
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user2, user1, 1000);
        // Impersonate vault
        vm.startPrank(address(vault));
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Redeem);
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

    function testCorreclyEnqueueReturningUser() external {
        // Impersonate vault
        vm.startPrank(address(vault));

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user2, user1, 1000);
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(2, user1, user2, 2000);
        emergencyWithdrawalQueue.enqueue(user1, user2, 2000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(3, user2, user1, 3000);
        emergencyWithdrawalQueue.enqueue(user2, user1, 3000, EmergencyWithdrawalQueue.RequestType.Withdraw);

        vm.stopPrank();

        assertEq(emergencyWithdrawalQueue.size(), 3);
    }

    function testDequeueSuccess() external {
        // Impersonate vault
        vm.startPrank(address(vault));
        // Only vault should be able to enqueue.
        emergencyWithdrawalQueue.enqueue(user2, user1, 1000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        emergencyWithdrawalQueue.enqueue(user1, user2, 2000, EmergencyWithdrawalQueue.RequestType.Redeem);
        emergencyWithdrawalQueue.enqueue(user2, user1, 3000, EmergencyWithdrawalQueue.RequestType.Withdraw);
        vm.stopPrank();

        vm.mockCall(address(vault), abi.encodeWithSelector(L2Vault.withdraw.selector), abi.encode(1000));
        vm.mockCall(address(vault), abi.encodeWithSelector(L2Vault.redeem.selector), abi.encode(2000));

        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(1, user2, user1, 1000);
        vm.expectCall(address(vault), abi.encodeWithSelector(L2Vault.withdraw.selector, 1000, user1, user2));
        emergencyWithdrawalQueue.dequeue();
        assertEq(emergencyWithdrawalQueue.size(), 2);

        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(2, user1, user2, 2000);
        vm.expectCall(address(vault), abi.encodeWithSelector(L2Vault.redeem.selector, 2000, user2, user1));
        vm.expectEmit(false, false, false, false);
        emit EmergencyWithdrawalQueueDequeue(3, user2, user1, 3000);
        vm.expectCall(address(vault), abi.encodeWithSelector(L2Vault.withdraw.selector, 3000, user1, user2));
        emergencyWithdrawalQueue.dequeueBatch(2);
        assertEq(emergencyWithdrawalQueue.size(), 0);
    }
}
