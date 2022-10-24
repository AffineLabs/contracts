// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {L2WormholeRouter} from "../polygon/L2WormholeRouter.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {EmergencyWithdrawalQueue} from "../polygon/EmergencyWithdrawalQueue.sol";

import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockL2Vault} from "./mocks/index.sol";

contract L2VaultTest is TestPlus {
    using stdStorage for StdStorage;

    MockL2Vault vault;
    MockERC20 asset;
    uint256 oneUSDC = 1_000_000;
    uint256 halfUSDC = oneUSDC / 2;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        asset = MockERC20(vault.asset());
        vault.setMockRebalanceDelta(0);
    }

    // Adding this since this test contract is used as a strategy
    function totalLockedValue() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event EmergencyWithdrawalQueueRequestDropped(
        uint256 indexed pos, address indexed owner, address indexed receiver, uint256 shares
    );

    function testDeploy() public {
        assertEq(vault.decimals(), asset.decimals() + 10);
        // this makes sure that the first time we assess management fees we get a reasonable number
        // since management fees are calculated based on block.timestamp - lastHarvest
        assertEq(vault.lastHarvest(), block.timestamp);

        // The bridge is unlocked to begin with
        assertTrue(vault.canTransferToL1());
        assertTrue(vault.canRequestFromL1());
    }

    function testDepositRedeem(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        // Running into overflow issues on the call to vault.redeem
        address user = address(this);
        asset.mint(user, amountAsset);

        uint256 expectedShares = uint256(amountAsset) * 1e8;
        // user gives max approval to vault for asset
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(address(user)), 0);

        uint256 assetsReceived = vault.redeem(expectedShares, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(assetsReceived, amountAsset);
    }

    function testDepositWithdraw(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        // shares = assets * totalShares / totalAssets but totalShares will actually be bigger than a uint128
        // so the `assets * totalShares` calc will overflow if using a uint128
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        // If vault is empty, assets are converted to shares at 1:1e8 ratio
        uint256 expectedShares = uint256(amountAsset) * 1e8; // cast to uint256 to prevent overflow

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, expectedShares);
        vault.deposit(amountAsset, user);

        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(user), 0);

        // vm.expectEmit(true, true, true, true);
        // emit Withdraw(user, user, user, amountAsset, expectedShares);
        // emit log_named_uint("expected  shares: ",  vault.convertToShares(uint(amountAsset)));
        vault.withdraw(amountAsset, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testMint(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        // If vault is empty, assets are converted to shares at 1:1e8 ratio
        uint256 expectedShares = uint256(amountAsset) * 1e8; // cast to uint256 to prevent overflow

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, expectedShares);
        vault.mint(expectedShares, user);

        assertEq(vault.balanceOf(user), expectedShares);
    }

    function testMinDeposit() public {
        address user = address(this);
        asset.mint(user, 100);
        asset.approve(address(vault), type(uint256).max);

        // If we're minting zero shares we revert
        vm.expectRevert("MIN_DEPOSIT_ERR");
        vault.deposit(0, user);

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

    /**
     * CROSS CHAIN REBALANCING
     */

    function testReceiveTVL() public {
        // No rebalancing should actually occur
        vault.setMockRebalanceDelta(1e6);

        vm.prank(alice);
        vm.expectRevert("Only wormhole router");
        vault.receiveTVL(0, false);

        // If L1 has received our last transfer, we can transfer again
        vault.setCanTransferToL1(false);
        vm.startPrank(vault.wormholeRouter());
        vault.receiveTVL(100, true);

        assertEq(vault.canTransferToL1(), true);
        assertEq(vault.l1TotalLockedValue(), 100);

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
        vault.receiveTVL(120, true);

        assertEq(vault.canTransferToL1(), true);
        assertEq(vault.l1TotalLockedValue(), 120);
    }

    function testLockedTVL() public {
        // No rebalancing should actually occur
        vault.setMockRebalanceDelta(1e6);
        assertEq(vault.lockedTVL(), 0);

        vault.setCanTransferToL1(false);
        vm.startPrank(vault.wormholeRouter());
        vault.receiveTVL(100, true);

        assertEq(vault.l1TotalLockedValue(), 100);
        assertEq(vault.lockedTVL(), 100);
        assertEq(vault.totalAssets(), 0);

        // Using up 50% of lockInterval unlocks 50% of tvl
        vm.warp(block.timestamp + vault.lockInterval() / 2);
        assertEq(vault.lockedTVL(), 50);
        assertEq(vault.totalAssets(), 50);

        // Using up all of lock interval unlocks all of tvl
        vm.warp(block.timestamp + vault.lockInterval());
        assertEq(vault.lockedTVL(), 0);
        assertEq(vault.totalAssets(), 100);
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

    function testL1ToL2RebalanceWithEmergencyWithdrawalQueueDebt() public {
        // Any call to the wormholerouter will do nothing
        vm.mockCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.requestFunds, (200)), "");
        // Simulate having 200 debt to emergency withdrawal queue.
        vm.mockCall(
            address(vault.emergencyWithdrawalQueue()),
            abi.encodeCall(EmergencyWithdrawalQueue.totalDebt, ()),
            abi.encode(200)
        );

        // L2 Vault has 100, L1 Vault has 300. L2 Vault has 200 debt to emergency withdrawal queue.
        // That means, L2 Vault currently need 300. 200 for safisfying the emergency withdrawal
        // queue and 100 to have 1:1 ratio with L1 Vault. So, L2 Vault will request 200 from
        // the L1 Vault.
        asset.mint(address(vault), 100);
        vm.startPrank(vault.wormholeRouter());
        vm.expectCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.requestFunds, (200)));
        vault.receiveTVL(300, false);

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

    function testL2ToL1RebalanceWithEmergencyWithdrawalQueueDebt() public {
        // Relevant calls to the wormholerouter and bridge escrow will do nothing, and we won't
        // actually attempt to bridge funds
        vm.mockCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.reportTransferredFund, (50)), "");
        vm.mockCall(address(vault.bridgeEscrow()), abi.encodeCall(BridgeEscrow.l2Withdraw, (50)), "");
        // Simulate having 50 debt to emergency withdrawal queue.
        vm.mockCall(
            address(vault.emergencyWithdrawalQueue()),
            abi.encodeCall(EmergencyWithdrawalQueue.totalDebt, ()),
            abi.encode(50)
        );

        // We have a tvl of 200 excluding the withdrawal queue, so each layer gets 100
        asset.mint(address(vault), 200);
        vm.startPrank(vault.wormholeRouter());
        vm.expectCall(vault.wormholeRouter(), abi.encodeCall(L2WormholeRouter.reportTransferredFund, (50)));
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
                Strings.toHexString(uint256(vault.GUARDIAN_ROLE()), 32)
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
        uint256 indexed pos, address indexed owner, address indexed receiver, uint256 amount
    );

    function testEmergencyWithdrawal(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        vm.expectEmit(true, true, true, false);
        emit EmergencyWithdrawalQueueEnqueue(1, user, user, vault.convertToShares(amountAsset));

        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.withdraw(amountAsset, user, user);
        assertEq(asset.balanceOf(user), 0);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );
        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testEmergencyWithdrawalWithRedeem(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        uint256 numShares = vault.convertToShares(amountAsset);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawalQueueEnqueue(1, user, user, numShares);

        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.redeem(numShares, user, user);
        assertEq(asset.balanceOf(user), 0);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(oneUSDC))
        );
        // Triggier emergency withdrawal queue enqueue.
        vault.withdraw(halfUSDC, alice, alice);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vm.expectRevert("L2Vault: min shares");
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(oneUSDC))
        );
        // Triggier emergency withdrawal queue enqueue.
        vault.redeem(halfUSDCInShare, alice, alice);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), oneUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vm.expectRevert("L2Vault: min shares");
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
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
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
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
        assertEq(price.num, 100 * 10 ** uint256(asset.decimals()));

        asset.mint(address(vault), 2e18);

        // initial price is $100, but if we increase tvl the price increases
        L2Vault.Number memory price2 = vault.detailedPrice();
        assertTrue(price2.num > price.num);
    }

    function testSettingForwarder() public {
        vm.prank(governance);
        address newForwarder = makeAddr("new_forwarder");
        vault.setTrustedForwarder(newForwarder);
        assertEq(vault.trustedForwarder(), newForwarder);

        // only gov can call
        vm.prank(alice);
        vm.expectRevert("Only Governance.");
        vault.setTrustedForwarder(address(0));
    }

    function testSetEwq() public {
        EmergencyWithdrawalQueue newQ = EmergencyWithdrawalQueue(makeAddr("new_queue"));
        vm.prank(governance);
        vault.setEwq(newQ);
        assertEq(address(vault.emergencyWithdrawalQueue()), address(newQ));

        // only gov can call
        vm.prank(alice);
        vm.expectRevert("Only Governance.");
        vault.setEwq(EmergencyWithdrawalQueue(address(0)));
    }

    function testSettingRebalanceDelta() public {
        vm.prank(governance);
        vault.setRebalanceDelta(100);
        assertEq(vault.rebalanceDelta(), 100);

        vm.prank(alice);
        vm.expectRevert("Only Governance.");
        vault.setRebalanceDelta(0);
    }
}
