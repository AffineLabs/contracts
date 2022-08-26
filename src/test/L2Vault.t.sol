// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { L2WormholeRouter } from "../polygon/L2WormholeRouter.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { BridgeEscrow } from "../BridgeEscrow.sol";
import { EmergencyWithdrawalQueue } from "../polygon/EmergencyWithdrawalQueue.sol";

import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockL2Vault } from "./mocks/index.sol";

contract L2VaultTest is TestPlus {
    using stdStorage for StdStorage;

    MockL2Vault vault;
    MockERC20 asset;
    uint256 oneUSDC = 1_000_000;
    uint256 halfUSDC = oneUSDC / 2;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        asset = MockERC20(vault.asset());
    }

    // Adding this since this test contract is used as a strategy
    function totalLockedValue() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event EmergencyWithdrawalQueueRequestDropped(
        uint256 indexed pos,
        address indexed owner,
        address indexed receiver,
        uint256 shares
    );

    function testDeploy() public {
        assertEq(vault.decimals(), asset.decimals());
        // this makes sure that the first time we assess management fees we get a reasonable number
        // since management fees are calculated based on block.timestamp - lastHarvest
        assertEq(vault.lastHarvest(), block.timestamp);

        // The bridge is unlocked to begin with
        assertTrue(vault.canTransferToL1());
        assertTrue(vault.canRequestFromL1());
    }

    function testDepositRedeem(uint128 amountAsset) public {
        vm.assume(amountAsset > 99);
        // Running into overflow issues on the call to vault.redeem
        address user = address(this);
        asset.mint(user, amountAsset);

        // user gives max approval to vault for asset
        asset.approve(address(vault), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, user, amountAsset, amountAsset / 100);
        vault.deposit(amountAsset, user);

        // If vault is empty, assets are converted to shares at 100:1
        uint256 numShares = vault.balanceOf(user);
        uint256 expectedShares = amountAsset / 100;
        assertEq(numShares, expectedShares);
        assertEq(asset.balanceOf(address(user)), 0);
        assertEq(asset.balanceOf(address(vault)), amountAsset);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, amountAsset, amountAsset / 100);
        uint256 assetsReceived = vault.redeem(numShares, user, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(assetsReceived, amountAsset);
    }

    function testDepositWithdraw(uint128 amountAsset) public {
        vm.assume(amountAsset > 99);
        // Using a uint128 since we multiply totalSupply by amountAsset in sharesFromTokens
        // Using a uint128 makes sure the calculation will not overflow
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, amountAsset / 100);
        vault.deposit(amountAsset, user);

        // If vault is empty, assets are converted to shares at 100:1
        assertEq(vault.balanceOf(user), amountAsset / 100);
        assertEq(asset.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, user, user, amountAsset, amountAsset / 100);
        vault.withdraw(amountAsset, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testMint(uint128 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        uint256 numShares = amountAsset / 100;
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), numShares * 100, numShares);
        vault.mint(numShares, user);

        // If vault is empty, assets are converted to shares at 100:1
        assertEq(vault.balanceOf(user), numShares);

        // E.g. is amountAsset is 201, numShares is 2 and we actually have 1 in asset left
        assertEq(asset.balanceOf(user), amountAsset - (numShares * 100));
        assertEq(asset.balanceOf(address(vault)), numShares * 100);
    }

    function testMinDeposit() public {
        address user = address(this);
        asset.mint(user, 100);
        asset.approve(address(vault), type(uint256).max);

        // shares = assets / 100. If you give less than 100 in assets we revert
        vm.expectRevert("MIN_DEPOSIT_ERR");
        vault.deposit(99, user);

        vault.deposit(100, user);
    }

    function testManagementFee() public {
        // Increase vault's total supply
        deal(address(vault), address(0), 1e18, true);

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
        changePrank(governance);
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestamp must be >= lastHarvest + lockInterval when harvesting
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        // Call harvest to update lastHarvest, note that no shares are minted here because
        // (block.timestamp - lastHarvest) = lockInterval + 1 =  3 hours + 1 second
        // and feeBps gets truncated to zero
        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        vm.warp(block.timestamp + vault.SECS_PER_YEAR() / 2);

        // Call harvest to trigger fee assessment
        vault.harvest(strategyList);

        // Check that fees were assesed in the correct amounts => Management fees are sent to governance address
        // 1/2 of 2% of the vault's supply should be minted to governance
        assertEq(vault.balanceOf(governance), (100 * 1e18) / 10_000);
    }

    function testLockedProfit() public {
        // Add this contract as a strategy
        changePrank(governance);
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestamp must be >= lastHarvest + lockInterval when harvesting
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        asset.mint(address(myStrat), 1e18);
        asset.approve(address(vault), type(uint256).max);

        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        assertEq(vault.lockedProfit(), 1e18);
        assertEq(vault.totalAssets(), 0);

        // Using up 50% of lockInterval unlocks 50% of profit
        vm.warp(block.timestamp + vault.lockInterval() / 2);
        assertEq(vault.lockedProfit(), 1e18 / 2);
        assertEq(vault.totalAssets(), 1e18 / 2);
    }

    /** CROSS CHAIN REBALANCING
     */

    function testReceiveTVL() public {
        vm.prank(alice);
        vm.expectRevert("Only wormhole router");
        vault.receiveTVL(0, false);

        // If L1 has received our last transfer, we can transfer again
        // We mint some money so that we don't trigger any actual rebalancing
        asset.mint(address(vault), 100);
        vault.setCanTransferToL1(false);
        vm.startPrank(vault.wormholeRouter());
        vault.receiveTVL(100, true);

        assertEq(vault.canTransferToL1(), true);
        assertEq(vault.L1TotalLockedValue(), 100);

        // If one of the bridge vars is locked, we just revert
        // canRequestFromL1 is false, canTransferToL1 is true
        vault.setCanRequestFromL1(false);
        vm.expectRevert("Rebalance in progress");
        vault.receiveTVL(120, true);

        // canRequestFromL1 is true, canTransferToL1 is false
        vault.setCanRequestFromL1(true);
        vault.setCanTransferToL1(false);
        vm.expectRevert("Rebalance in progress");
        vault.receiveTVL(120, false); // if `received` is true then canTransferToL1 will be true

        // canRequestFromL1 is false, canTransferToL1 is false (we should actually never get in this state)
        vault.setCanRequestFromL1(false);
        vault.setCanTransferToL1(false);
        vm.expectRevert("Rebalance in progress");
        vault.receiveTVL(120, false);

        // canRequestFromL1 is true, canTransferToL1 is true
        vault.setCanRequestFromL1(true);
        vault.setCanTransferToL1(true);
        asset.mint(address(vault), 20); // mint so that we don't try to request money from L1
        vault.receiveTVL(120, true);

        assertEq(vault.canTransferToL1(), true);
        assertEq(vault.L1TotalLockedValue(), 120);
    }

    function testL1ToL2Rebalance() public {
        // Any call to the wormholerouter will do nothing
        vm.mockCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.requestFunds, (25)), "");

        // The L1 vault has to send us 25 to meet the 1:1 ratio between layers
        asset.mint(address(vault), 100);
        vm.startPrank(vault.wormholeRouter());
        vm.expectCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.requestFunds, (25)));
        vault.receiveTVL(150, false);

        assertEq(vault.canRequestFromL1(), false);
    }

    function testL2ToL1Rebalance() public {
        // Any call to the wormholerouter will do nothing, and we won't actually attempt to bridge funds
        vm.mockCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.reportTransferredFund, (25)), "");
        vm.mockCall(address(vault.bridgeEscrow()), abi.encodeCall(BridgeEscrow.l2Withdraw, (25)), "");

        // L2Vault has to send 25 to meet the 1:1 ratio between layers
        asset.mint(address(vault), 100);
        vm.startPrank(vault.wormholeRouter());
        vm.expectCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.reportTransferredFund, (25)));
        vault.receiveTVL(50, false);

        assertEq(vault.canTransferToL1(), false);
    }

    function testWithdrawalFee() public {
        vm.prank(governance);
        vault.setWithdrawalFee(50);

        uint256 amountAsset = 1e18;

        changePrank(alice);
        asset.mint(alice, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, alice);

        vault.redeem(vault.balanceOf(alice), alice, alice);
        assertEq(vault.balanceOf(alice), 0);

        // User gets the original amount with 50bps deducted
        assertEq(asset.balanceOf(alice), (amountAsset * (10_000 - 50)) / 10_000);
        // Governance gets the 50bps fee
        assertEq(asset.balanceOf(vault.governance()), (amountAsset * 50) / 10_000);
    }

    function testSettingFees() public {
        changePrank(governance);
        vault.setManagementFee(300);
        assertEq(vault.managementFee(), 300);
        vault.setWithdrawalFee(10);
        assertEq(vault.withdrawalFee(), 10);

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        vault.setManagementFee(300);
        vm.expectRevert("Only Governance.");
        vault.setWithdrawalFee(10);
    }

    function testVaultPause() public {
        changePrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1e18, address(this), address(this));

        vault.unpause();

        vm.stopPrank();
        testDepositWithdraw(1e18);

        // Only the harvesterRole address can call pause or unpause
        string memory errString = string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role ",
                Strings.toHexString(uint256(vault.harvesterRole()), 32)
            )
        );

        bytes memory errorMsg = abi.encodePacked(errString);

        vm.expectRevert(errorMsg);
        changePrank(alice);
        vault.pause();

        vm.expectRevert(errorMsg);
        vault.unpause();
    }

    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    function testEmergencyWithdrawal(uint128 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        vm.startPrank(user);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user, user, vault.previewWithdraw(amountAsset));

        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.withdraw(amountAsset, user, user);
        assertEq(asset.balanceOf(user), 0);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );
        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testEmergencyWithdrawalWithRedeem(uint128 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        vm.startPrank(user);
        uint256 numShares = vault.convertToShares(amountAsset);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user, user, numShares);

        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.redeem(numShares, user, user);
        assertEq(asset.balanceOf(user), 0);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vault.emergencyWithdrawalQueue().dequeue();

        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testEmergencyWithdrawalQueueNotStarved() public {
        (address user1, address user2) = (address(1), address(2));
        asset.mint(user1, halfUSDC);
        asset.mint(user2, halfUSDC);

        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(halfUSDC, user1);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), halfUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(halfUSDC))
        );

        // This will trigger an emergency withdrawal queue enqueue as there is no asset in L2 vault.
        vault.withdraw(halfUSDC, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(halfUSDC, user2);

        // Now the vault has half USDC, but if user2 wants to withdraw half USDC, it will
        // again trigger an emergency withdrawal queue enqueue as this half USDC is reserved
        // for withdrawals in the emergency withdrawal queue.
        vault.withdraw(halfUSDC, user2, user2);

        assertEq(vault.emergencyWithdrawalQueue().size(), 2);
        vm.stopPrank();

        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(asset.balanceOf(user1), halfUSDC);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), halfUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(asset.balanceOf(user2), halfUSDC);
    }

    function testCheckEmeregencyWithdrawalQueueBeforeWithdraw() public {
        asset.mint(alice, oneUSDC);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(oneUSDC, alice);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(oneUSDC))
        );
        // Triggier emergency withdrawal queue enqueue.
        vault.withdraw(halfUSDC, alice, alice);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vm.expectRevert("Not enough share available in owners balance");
        // At this point alice can withdraw at most half usdc. So trying to withdraw
        // half usdc + 1 should fail.
        vault.withdraw(halfUSDC + 1, alice, alice);

        vault.withdraw(halfUSDC, alice, alice);
        vault.emergencyWithdrawalQueue().dequeue();

        assertEq(asset.balanceOf(alice), oneUSDC);
    }

    function testCheckEmeregencyWithdrawalQueueBeforeRedeem() public {
        asset.mint(alice, oneUSDC);
        uint256 halfUSDCInShare = vault.previewWithdraw(halfUSDC);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(oneUSDC, alice);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(oneUSDC))
        );
        // Triggier emergency withdrawal queue enqueue.
        vault.redeem(halfUSDCInShare, alice, alice);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vm.expectRevert("Not enough share available in owners balance");
        // At this point alice can redeem at most half usdc worth of vault token. So trying
        // to redeem half usdc worth of vault token + 1 should fail.
        vault.redeem(halfUSDCInShare + 1, alice, alice);

        vault.redeem(halfUSDCInShare, alice, alice);
        vault.emergencyWithdrawalQueue().dequeue();

        assertEq(asset.balanceOf(alice), oneUSDC);
    }

    function testEmergencyWithdrawalRequestDrop() public {
        asset.mint(alice, oneUSDC);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(oneUSDC, alice);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), halfUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(halfUSDC))
        );

        // This will trigger an emergency withdrawal queue enqueue as there is no asset in L2 vault.
        vault.withdraw(oneUSDC, alice, alice);
        // Transfer ALP tokens to bob.
        vault.transfer(bob, vault.balanceOf(alice));

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), halfUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueRequestDropped(1, alice, alice, vault.convertToShares(oneUSDC));
        vault.emergencyWithdrawalQueue().dequeue();
        // The emergency withdrawal request should be dropped.
        assertEq(asset.balanceOf(alice), 0);
    }

    function testDetailedPrice() public {
        // This function should work even if there is nothing in the vault
        L2Vault.Number memory price = vault.detailedPrice();
        assertEq(price.num, 10**vault.decimals());

        address user = address(this);
        asset.mint(user, 2e18);
        asset.approve(address(vault), type(uint256).max);

        vault.deposit(1e18, user);
        asset.transfer(address(vault), 1e18);

        // initial price is $100, but if we increase tvl by two it will be 200
        L2Vault.Number memory price2 = vault.detailedPrice();
        assertEq(price2.num, 200 * 10**vault.decimals());
    }

    function testSettingForwarder() public {
        changePrank(governance);
        address newForwarder = 0x8f954E7D7ec3A31D9568316fb0F472B03fc2a7d5;
        vault.setTrustedForwarder(newForwarder);
        assertEq(vault.trustedForwarder(), newForwarder);

        // only gov can call
        changePrank(alice);
        vm.expectRevert("Only Governance.");
        vault.setTrustedForwarder(address(0));
    }

    function testSettingRebalanceDelta() public {
        changePrank(governance);
        vault.setRebalanceDelta(100);
        assertEq(vault.rebalanceDelta(), 100);

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        vault.setRebalanceDelta(0);
    }

    function testAssetLimit() public {
        vm.prank(governance);
        vault.setAssetLimit(1000);

        asset.mint(address(this), 2000);
        asset.approve(address(vault), type(uint256).max);

        vault.deposit(500, address(this));
        assertEq(asset.balanceOf(address(this)), 1500);

        // We only deposit 500 because the limit is 500 and 500 is already in the vault
        vault.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);

        vm.expectRevert("MIN_DEPOSIT_ERR");
        vault.deposit(200, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);
    }

    function testAssetLimitMint() public {
        vm.prank(governance);
        vault.setAssetLimit(1000);

        asset.mint(address(this), 2000);
        asset.approve(address(vault), type(uint256).max);

        vault.mint(5, address(this));
        assertEq(asset.balanceOf(address(this)), 1500);

        // We only deposit 500 because the limit is 500 and 500 is already in the vault
        vault.mint(10, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);

        vm.expectRevert("MIN_DEPOSIT_ERR");
        vault.mint(20, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);
    }

    function testTearDown() public {
        // Give alice and bob some shares
        deal(address(vault), alice, 1e18, true);
        deal(address(vault), bob, 1e18, true);

        deal(address(asset), address(vault), 2e18);

        // Call teardown and make sure they get money back
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        vm.prank(governance);
        vault.tearDown(users);

        assertEq(asset.balanceOf(alice), 1e18);
        assertEq(asset.balanceOf(bob), 1e18);
        assertEq(asset.balanceOf(address(vault)), 0);
    }
}
