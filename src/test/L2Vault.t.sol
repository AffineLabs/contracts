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
    L2Vault vault;
    MockERC20 token;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        token = MockERC20(vault.asset());
    }

    // Adding this since this test contract is used as a strategy
    function totalLockedValue() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function testDepositRedeem(uint128 amountToken) public {
        // Running into overflow issues on the call to vault.redeem
        uint256 amountToken = uint256(amountToken);
        address user = address(this);
        token.mint(user, amountToken);

        // user gives max approval to vault for token
        token.approve(address(vault), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountToken, amountToken);
        vault.deposit(amountToken, address(this));

        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(vault)), amountToken);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), user, user, amountToken, amountToken);
        uint256 assetsReceived = vault.redeem(numShares, user, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(assetsReceived, amountToken);
    }

    function testDepositWithdraw(uint64 amountToken) public {
        // Using a uint64 since we multiply totalSupply by amountToken in sharesFromTokens
        // Using a uint64 makes sure the calculation will not overflow
        address user = address(this);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountToken, amountToken);
        vault.deposit(amountToken, address(this));

        // If vault is empty, tokens are converted to shares at 1:1
        assertEq(vault.balanceOf(user), amountToken);
        assertEq(token.balanceOf(user), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), address(this), address(this), amountToken, amountToken);
        vault.withdraw(amountToken, address(this), address(this));
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testManagementFee() public {
        // Add total supply => occupies ERC20Upgradeable which inherits from two contracts with storage,
        // One contract has one slots and the other has 50 slots. totalSupply is at slot three in ERC20Up, so
        // the slot would is number 50 + 1 + 3 = 54 (index 53)
        vm.store(address(vault), bytes32(uint256(53)), bytes32(uint256(1e18)));

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

        token.mint(address(myStrat), 1e18);
        token.approve(address(vault), type(uint256).max);

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
        uint256 amountToken = 1e18;
        vault.setWithdrawalFee(50);

        address user = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik
        vm.startPrank(user);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amountToken, user);

        vault.redeem(vault.balanceOf(user), user, user);
        assertEq(vault.balanceOf(user), 0);

        // User gets the original amount with 50bps deducted
        assertEq(token.balanceOf(user), (amountToken * (10_000 - 50)) / 10_000);
        // Governance gets the 50bps fee
        assertEq(token.balanceOf(vault.governance()), (amountToken * 50) / 10_000);
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
        vault.togglePause();

        vm.expectRevert("Pausable: paused");
        vault.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1e18, address(this), address(this));

        vault.togglePause();
        testDepositWithdraw(1e18);
    }

    event EmergencyWithdrawalQueueEnqueue(
        uint256 indexed pos,
        EmergencyWithdrawalQueue.RequestType requestType,
        address indexed owner,
        address indexed receiver,
        uint256 amount
    );

    function testEmergencyWithdrawal(uint128 amountToken) public {
        address user = address(this);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amountToken, address(this));

        // simulate vault assets being transferred to L1.
        token.burn(address(vault), amountToken);
        vm.startPrank(user);

        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawalQueueEnqueue(1, EmergencyWithdrawalQueue.RequestType.Withdraw, user, user, amountToken);
        // Trigger emergency withdrawal as vault doesn't have any asset.
        vault.withdraw(amountToken, user, user);
        assertEq(token.balanceOf(user), 0);
        // Simulate funds being bridged from L1 to L2 vault.
        token.mint(address(vault), amountToken);
        vault.emergencyWithdrawalQueue().dequeue();
        assertEq(token.balanceOf(user), amountToken);
    }
}
