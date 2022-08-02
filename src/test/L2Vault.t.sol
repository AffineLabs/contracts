// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { Deploy } from "./Deploy.sol";
import { EmergencyWithdrawalQueue } from "../polygon/EmergencyWithdrawalQueue.sol";

contract L2VaultTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
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

    function testDeploy() public {
        // this makes sure that the first time we assess management fees we get a reasonable number
        // since management fees are calculated based on block.timestamp - lastHarvest
        assertEq(vault.lastHarvest(), block.timestamp);
    }

    function testDepositRedeem(uint128 amountAsset) public {
        // Running into overflow issues on the call to vault.redeem
        address user = address(this);
        asset.mint(user, amountAsset);

        // user gives max approval to vault for asset
        asset.approve(address(vault), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, amountAsset);
        vault.deposit(amountAsset, address(this));

        // If vault is empty, assets are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountAsset);
        assertEq(asset.balanceOf(address(user)), 0);
        assertEq(asset.balanceOf(address(vault)), amountAsset);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), user, user, amountAsset, amountAsset);
        uint256 assetsReceived = vault.redeem(numShares, user, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(assetsReceived, amountAsset);
    }

    function testDepositWithdraw(uint128 amountAsset) public {
        // Using a uint64 since we multiply totalSupply by amountAsset in sharesFromTokens
        // Using a uint64 makes sure the calculation will not overflow
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, amountAsset);
        vault.deposit(amountAsset, address(this));

        // If vault is empty, assets are converted to shares at 1:1
        assertEq(vault.balanceOf(user), amountAsset);
        assertEq(asset.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), address(this), address(this), amountAsset, amountAsset);
        vault.withdraw(amountAsset, address(this), address(this));
        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testManagementFee() public {
        // Increase vault's total supply
        deal(address(vault), address(0), 1e18, true);

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
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
        assertEq(vault.balanceOf(address(this)), (100 * 1e18) / 10_000);
    }

    function testLockedProfit() public {
        // Add this contract as a strategy
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestap must be >= lastHarvest + lockInterval when harvesting
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

    function testWithdrawalFee() public {
        uint256 amountAsset = 1e18;
        vault.setWithdrawalFee(50);

        address user = mkaddr("vitalik"); // vitalik
        vm.startPrank(user);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        vault.redeem(vault.balanceOf(user), user, user);
        assertEq(vault.balanceOf(user), 0);

        // User gets the original amount with 50bps deducted
        assertEq(asset.balanceOf(user), (amountAsset * (10_000 - 50)) / 10_000);
        // Governance gets the 50bps fee
        assertEq(asset.balanceOf(vault.governance()), (amountAsset * 50) / 10_000);
    }

    function testSettingFees() public {
        vault.setManagementFee(300);
        assertEq(vault.managementFee(), 300);
        vault.setWithdrawalFee(10);
        assertEq(vault.withdrawalFee(), 10);

        vm.startPrank(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045);
        vm.expectRevert("Only Governance.");
        vault.setManagementFee(300);
        vm.expectRevert("Only Governance.");
        vault.setWithdrawalFee(10);
    }

    function testVaultPause() public {
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1e18, address(this), address(this));

        vault.unpause();
        testDepositWithdraw(1e18);
    }

    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        EmergencyWithdrawalQueue.RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    function testEmergencyWithdrawal(uint128 amountAsset) public {
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, address(this));

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        vm.startPrank(user);

        if (amountAsset > 0) {
            vm.expectEmit(true, true, false, true);
            emit EmergencyWithdrawalQueueEnqueue(
                1,
                EmergencyWithdrawalQueue.RequestType.Withdraw,
                user,
                user,
                amountAsset
            );
        }
        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.withdraw(amountAsset, user, user);
        assertEq(asset.balanceOf(user), 0);
        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        if (amountAsset > 0) {
            vault.emergencyWithdrawalQueue().dequeue();
        }
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function testEmergencyWithdrawalWithRedeem(uint128 amountAsset) public {
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, address(this));

        // simulate vault assets being transferred to L1.
        asset.burn(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(amountAsset))
        );

        vm.startPrank(user);
        if (amountAsset > 0) {
            vm.expectEmit(true, true, false, true);
            emit EmergencyWithdrawalQueueEnqueue(
                1,
                EmergencyWithdrawalQueue.RequestType.Redeem,
                user,
                user,
                amountAsset
            );
        }
        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.redeem(amountAsset, user, user);
        assertEq(asset.balanceOf(user), 0);

        // Simulate funds being bridged from L1 to L2 vault.
        asset.mint(address(vault), amountAsset);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );
        if (amountAsset > 0) {
            vault.emergencyWithdrawalQueue().dequeue();
        }
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

        asset.mint(address(vault), halfUSDC);
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(0))
        );

        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(asset.balanceOf(user2), halfUSDC);
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
        L2Vault.Number memory price2 = vault.detailedPrice();
        assertEq(price2.num, 2 * 10**vault.decimals());
    }

    function testSettingForwarder() public {
        address newForwarder = 0x8f954E7D7ec3A31D9568316fb0F472B03fc2a7d5;
        vault.setTrustedForwarder(newForwarder);
        assertEq(vault.trustedForwarder(), newForwarder);

        // only gov can call
        vm.prank(newForwarder);
        vm.expectRevert("Only Governance.");
        vault.setTrustedForwarder(address(0));
    }

    function testSettingRebalanceDelta() public {
        vault.setRebalanceDelta(100);
        assertEq(vault.rebalanceDelta(), 100);

        vm.prank(0x8f954E7D7ec3A31D9568316fb0F472B03fc2a7d5);
        vm.expectRevert("Only Governance.");
        vault.setRebalanceDelta(0);
    }
}
