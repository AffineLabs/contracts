// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Vault, ERC721, VaultErrors} from "src/vaults/Vault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {BaseVault} from "src/vaults/cross-chain-vault/audited/BaseVault.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";

import {UltraLRT, Math} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {EigenDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/EigenDelegator.sol";
import {DelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";

import {console2} from "forge-std/console2.sol";

contract TmpDelegator is EigenDelegator {
    function version() public pure returns (uint256) {
        return 100;
    }
}

contract TmpUltraLRT is UltraLRT {
    function test() public returns (uint256) {
        return 100;
    }
}

contract UltraLRTTest is TestPlus {
    UltraLRT vault;
    ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
    IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
    uint256 initAssets;
    WithdrawalEscrowV2 escrow;

    function setUp() public {
        vm.createSelectFork("ethereum", 19_771_000);
        // ultra LRT impl
        UltraLRT impl = new UltraLRT();
        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(beacon), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        vault = UltraLRT(address(proxy));

        // set delegator factory
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        initAssets = 10 ** asset.decimals();
        initAssets *= 100;

        // add withdrawal escrow
        escrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(escrow);

        // create 3 delegator
        for (uint8 i = 0; i < 3; i++) {
            vm.prank(governance);
            vault.createDelegator(operator);
        }
    }

    function _getAsset(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        IStEth(address(asset)).submit{value: amount}(address(0));
        return asset.balanceOf(to);
    }

    function testDeposit() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(alice);
        asset.approve(address(vault), stEth);
        vm.prank(alice);
        vault.deposit(stEth, alice);

        console2.log("vault balance %s", vault.balanceOf(alice));

        assertEq(vault.balanceOf(alice), stEth * 1e8);
    }

    function testMint() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(alice);
        asset.approve(address(vault), stEth);
        uint256 sharesToMint = vault.previewDeposit(stEth);
        vm.prank(alice);
        vault.mint(sharesToMint, alice);

        assertEq(vault.balanceOf(alice), sharesToMint);
    }

    function testDepositMintOverMax() public {
        vm.expectRevert();
        vault.deposit(type(uint256).max, alice);
        vm.expectRevert();
        vault.mint(type(uint256).max, alice);
    }

    function testWithdrawFull() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        vm.prank(alice);
        vault.withdraw(assets, alice, alice);

        // alice st eth balance
        assertEq(asset.balanceOf(alice), assets);
        assertEq(vault.totalSupply(), 0);
    }

    function testRedeem() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        // alice st eth balance
        assertEq(asset.balanceOf(alice), assets);
        assertEq(vault.totalSupply(), 0);
    }

    function testWithdrawAndRedeemOverMax() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(assets + 1, alice, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.redeem(shares + 1, alice, alice);
    }

    function testWithdrawAndRedeemByAllowance() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);
        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.withdraw(assets / 2, bob, alice);
        assertApproxEqAbs(asset.balanceOf(bob), assets / 2, 100);
        assertApproxEqAbs(vault.balanceOf(alice), shares / 2, 100);

        uint256 remShares = vault.balanceOf(alice);

        vm.prank(bob);
        vault.redeem(remShares, bob, alice);

        assertApproxEqAbs(asset.balanceOf(bob), assets, 100);
        assertApproxEqAbs(vault.balanceOf(alice), 0, 100);

        // test more than allowance
        testDeposit();
        shares = vault.balanceOf(alice);
        assets = vault.convertToAssets(shares);

        vm.prank(alice);
        vault.approve(bob, shares / 10);

        // withdraw more than allowance
        vm.expectRevert();
        vm.prank(bob);
        vault.redeem(shares / 10 + 1, bob, alice);
    }

    function testStEthTransferIssueBuffer() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        IDelegator d0 = vault.delegatorQueue(0);

        vm.prank(governance);
        vault.delegateToDelegator(address(d0), 500);

        assertTrue(vault.canWithdraw(assets));
        vm.prank(alice);
        vault.withdraw(assets, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertApproxEqAbs(asset.balanceOf(alice), assets, 1000);
        // assertTrue((assets - asset.balanceOf(alice)) > 500);
    }

    function testCreateDelegator() public {
        testDeposit();
        uint256 oldDelegatorCount = vault.delegatorCount();
        // no gov
        vm.expectRevert();
        vault.createDelegator(operator);

        vm.prank(governance);
        vault.createDelegator(operator);
        assertEq(vault.delegatorCount(), oldDelegatorCount + 1);

        // create max delegator
        vm.startPrank(governance);
        while (vault.delegatorCount() < vault.MAX_DELEGATOR()) {
            vault.createDelegator(operator);
        }
        vm.expectRevert();
        vault.createDelegator(operator);

        // test
        UltraLRT dummy = new UltraLRT();
        dummy.initialize(governance, address(asset), address(vault.beacon()), "uLRT", "uLRT");

        vm.expectRevert();
        dummy.createDelegator(operator);
    }

    function testDelegateToDelegator() public {
        testDeposit();
        IDelegator delegator = vault.delegatorQueue(0);
        console2.log("delegator %s", address(delegator));

        uint256 assets = vault.totalAssets();

        // delegate with non-approved address
        vm.expectRevert();
        vault.delegateToDelegator(address(delegator), assets);

        // delegate to invalid address
        vm.expectRevert();
        vm.prank(governance);
        vault.delegateToDelegator(address(this), assets);

        // delegate more than assets
        vm.expectRevert();
        vm.prank(governance);
        vault.delegateToDelegator(address(this), 2 * assets);

        vm.prank(governance);
        vault.delegateToDelegator(address(delegator), assets);

        assertApproxEqAbs(vault.totalAssets(), assets, 100);

        assertApproxEqAbs(delegator.totalLockedValue(), assets, 100);

        // can withdraw should be false
        assertTrue(!vault.canWithdraw(100_000_000));
        assertApproxEqAbs(vault.vaultAssets(), 0, 100);

        vm.prank(governance);
        vm.expectRevert();
        vault.delegateToDelegator(address(delegator), assets);
    }

    function testDropDelegator() public {
        testDelegateToDelegator();
        uint256 oldDelegatorCount = vault.delegatorCount();
        // drop a random validator
        vm.prank(governance);
        vm.expectRevert();
        vault.dropDelegator(alice);
        assertEq(oldDelegatorCount, vault.delegatorCount());

        // drop last validator
        address _del = address(vault.delegatorQueue(oldDelegatorCount - 1));
        vm.prank(governance);
        vault.dropDelegator(_del);
        assertEq(oldDelegatorCount - 1, vault.delegatorCount());

        // drop non zero tvl validator

        _del = address(vault.delegatorQueue(0));
        vm.prank(governance);
        vm.expectRevert();
        vault.dropDelegator(_del);

        EigenDelegator del = new EigenDelegator();

        vm.prank(governance);
        vm.expectRevert();
        vault.dropDelegator(address(del));
    }

    function testPauseAndUnpause() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(governance);
        vault.pause();

        // Test deposit when paused
        vm.prank(alice);
        asset.approve(address(vault), stEth);
        try vault.deposit(stEth, alice) {
            assertTrue(false, "Deposit should fail when paused");
        } catch Error(string memory reason) {
            assertEq(reason, "Pausable: paused");
        }

        // Test withdraw when paused
        try vault.withdraw(stEth, alice, alice) {
            assertTrue(false, "Withdraw should fail when paused");
        } catch Error(string memory reason) {
            assertEq(reason, "Pausable: paused");
        }

        // Unpause
        vm.prank(governance);
        vault.unpause();

        // Test deposit when unpaused
        vm.prank(alice);
        vault.deposit(stEth, alice);
        assertEq(vault.balanceOf(alice), stEth * 1e8, "Deposit failed after unpausing");

        // Test withdraw when unpaused
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);
        vm.prank(alice);
        vault.withdraw(assets, alice, alice);
        assertEq(asset.balanceOf(alice), assets, "Withdraw failed after unpausing");
    }

    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (prefixBytes.length > strBytes.length) {
            return false;
        }
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        return true;
    }

    function testPermissionedFunctions() public {
        uint256 stEth = _getAsset(alice, initAssets);

        testDelegateToDelegator();
        IDelegator delegator = vault.delegatorQueue(0);

        vm.prank(bob); // bob is not a harvester or governance

        // Test endEpoch
        try vault.endEpoch() {
            assertTrue(false, "endEpoch should fail when not called by harvester or governance");
        } catch Error(string memory reason) {
            assertTrue(startsWith(reason, "AccessControl"), "Error reason does not start with 'AccessControl'");
        }

        // Test liquidationRequest
        try vault.liquidationRequest(stEth) {
            assertTrue(false, "liquidationRequest should fail when not called by harvester or governance");
        } catch Error(string memory reason) {
            assertTrue(startsWith(reason, "AccessControl"), "Error reason does not start with 'AccessControl'");
        }

        // Test delegatorWithdrawRequest
        try vault.delegatorWithdrawRequest(delegator, stEth) {
            assertTrue(false, "delegatorWithdrawRequest should fail when not called by harvester or governance");
        } catch Error(string memory reason) {
            assertTrue(startsWith(reason, "AccessControl"), "Error reason does not start with 'AccessControl'");
        }

        // Test resolveDebt
        try vault.resolveDebt() {
            assertTrue(false, "resolveDebt should fail when not called by harvester or governance");
        } catch Error(string memory reason) {
            assertTrue(startsWith(reason, "AccessControl:"), "Error reason does not start with 'AccessControl'");
        }
    }

    function testSetWithdrawalQueue() public {
        testDelegateToDelegator();
        IDelegator delegator = vault.delegatorQueue(0);

        uint256 vaultShares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(vaultShares);
        // 99999999999999999997 asset
        // shares 96834476546864619822

        uint256 reqAssets = delegator.withdrawableAssets();

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(reqAssets), stEthStrategy.shares(address(delegator)));
        vm.prank(alice);
        uint256 blockNumber = block.number;

        vault.withdraw(assets, alice, alice);

        vm.prank(governance);
        vault.endEpoch();

        vm.prank(governance);
        vault.liquidationRequest(assets);

        // prep for withdraw
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNumber),
            strategies: strategies,
            shares: shares
        });
        vm.prank(governance);
        EigenDelegator(address(delegator)).completeWithdrawalRequest(params);

        vm.prank(governance);
        vault.collectDelegatorDebt();
        vm.prank(governance);
        vault.harvest();

        vm.prank(governance);
        vault.resolveDebt();

        escrow.redeem(alice, 0);
        assertApproxEqAbs(asset.balanceOf(address(alice)), assets, 100);
    }

    function testPause() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(alice);
        asset.approve(address(vault), stEth);

        // pause
        vm.prank(governance);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        vault.deposit(stEth, alice);

        // unpause
        vm.prank(governance);
        vault.unpause();

        vm.prank(alice);
        vault.deposit(stEth, alice);
    }

    function testDepositPause() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(alice);
        asset.approve(address(vault), 3 * stEth);

        vm.prank(alice);
        vault.deposit(stEth, alice);

        // unpause
        vm.prank(governance);
        vault.pauseDeposit();

        console2.log("Deposit pause %s", vault.depositPaused());

        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(stEth, alice);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        assertApproxEqAbs(asset.balanceOf(alice), stEth, 10);
        stEth = _getAsset(alice, initAssets);
        // // unpause deposit
        vm.prank(governance);
        vault.unpauseDeposit();
        vm.startPrank(alice);
        asset.approve(address(vault), stEth);
        vault.deposit(stEth, alice);
    }

    function testMultipleHarvest() public {
        vm.prank(governance);
        vault.harvest();
        // should revert before 24 hours
        vm.expectRevert();
        vm.prank(governance);
        vault.harvest();
    }

    function testProfitHarvest() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.startPrank(alice);
        asset.approve(address(vault), stEth);
        vault.deposit(stEth, alice);

        vm.startPrank(governance);
        vault.delegateToDelegator(address(vault.delegatorQueue(0)), stEth / 2);
        vault.delegateToDelegator(address(vault.delegatorQueue(0)), asset.balanceOf(address(vault)));

        uint256 currentTVL = vault.totalAssets();
        vm.stopPrank();

        _getAsset(address(vault.delegatorQueue(0)), initAssets);
        _getAsset(address(vault.delegatorQueue(1)), initAssets);

        vm.startPrank(governance);
        vault.harvest();

        vm.expectRevert();
        vault.harvest();

        assertApproxEqAbs(vault.lockedProfit(), 2 * initAssets, 100);

        assertApproxEqAbs(vault.totalAssets(), stEth, 100);

        vm.warp(block.timestamp + 24 * 3600);
        assertApproxEqAbs(vault.totalAssets(), stEth * 3, 100);
        assertEq(vault.lockedProfit(), 0);
    }

    function testLossHarvest() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.startPrank(alice);
        asset.approve(address(vault), stEth);
        vault.deposit(stEth, alice);

        vm.startPrank(governance);
        vault.delegateToDelegator(address(vault.delegatorQueue(0)), stEth / 2);
        vault.delegateToDelegator(address(vault.delegatorQueue(1)), asset.balanceOf(address(vault)));

        uint256 currentTVL = vault.totalAssets();
        vm.stopPrank();

        // withdraw 10% of shares to incur loss
        uint256 toWithdrawPerDelegator = stEth / 10;

        uint256 withdrawableStEthShares = stEthStrategy.underlyingToShares(toWithdrawPerDelegator);

        vm.prank(governance);

        //
        IDelegator d1 = vault.delegatorQueue(0);
        IDelegator d2 = vault.delegatorQueue(1);
        vm.prank(governance);
        vault.delegatorWithdrawRequest(d1, toWithdrawPerDelegator);
        vm.prank(governance);
        vault.delegatorWithdrawRequest(d2, toWithdrawPerDelegator);

        uint256 blockNumber = block.number;
        // withdraw from

        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(d1),
            delegatedTo: operator,
            withdrawer: address(d1),
            nonce: 0,
            startBlock: uint32(blockNumber),
            strategies: strategies,
            shares: shares
        });
        // withdraw from delegator 0
        vm.prank(governance);
        EigenDelegator(address(d1)).completeWithdrawalRequest(params);

        // withdraw from delegator 1
        params[0].staker = address(d2);
        params[0].withdrawer = address(d2);

        vm.prank(governance);
        EigenDelegator(address(d2)).completeWithdrawalRequest(params);

        console2.log(asset.balanceOf(address(d1)));
        console2.log(asset.balanceOf(address(d2)));

        uint256 d1Assets = asset.balanceOf(address(d1));
        uint256 d2Assets = asset.balanceOf(address(d2));

        vm.prank(address(d1));
        asset.transfer(address(this), d1Assets);
        vm.prank(address(d2));
        asset.transfer(address(this), d2Assets);

        console2.log("tvl %s", vault.totalAssets());
        assertApproxEqAbs(vault.totalAssets(), stEth, 100);

        // harvest loss
        vm.prank(governance);
        vault.harvest();

        assertApproxEqAbs(vault.totalAssets(), stEth - d1Assets - d2Assets, 100);
    }

    function testUpgradeBeacon() public {
        DelegatorBeacon beacon = DelegatorBeacon(vault.beacon());
        TmpDelegator impl = new TmpDelegator();
        vm.prank(vault.governance());

        beacon.update(address(impl));

        assertEq(TmpDelegator(address(vault.delegatorQueue(0))).version(), 100);
    }

    function testWithdrawalQueueWithDelegatorUpgrade() public {
        testDelegateToDelegator();
        IDelegator delegator = vault.delegatorQueue(0);

        testUpgradeBeacon();

        uint256 vaultShares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(vaultShares);
        // 99999999999999999997 asset
        // shares 96834476546864619822

        uint256 reqAssets = delegator.withdrawableAssets();

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(reqAssets), stEthStrategy.shares(address(delegator)));
        vm.prank(alice);
        uint256 blockNumber = block.number;

        vault.withdraw(assets, alice, alice);

        vm.prank(governance);
        vault.endEpoch();

        vm.prank(governance);
        vault.liquidationRequest(assets);

        // prep for withdraw
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNumber),
            strategies: strategies,
            shares: shares
        });
        vm.prank(governance);
        EigenDelegator(address(delegator)).completeWithdrawalRequest(params);

        vm.prank(governance);
        vault.collectDelegatorDebt();
        vm.prank(governance);
        vault.harvest();

        vm.prank(governance);
        vault.resolveDebt();

        escrow.redeem(alice, 0);
        assertApproxEqAbs(asset.balanceOf(address(alice)), assets, 100);
    }

    function testUpgradeVault() public {
        TmpUltraLRT newImpl = new TmpUltraLRT();

        address preGov = vault.governance();

        vm.expectRevert();
        TmpUltraLRT(address(vault)).test();

        vm.expectRevert();
        vault.upgradeTo(address(newImpl));

        vm.prank(governance);
        vault.upgradeTo(address(newImpl));

        assertEq(TmpUltraLRT(address(vault)).test(), 100);
        assertEq(vault.governance(), preGov);
    }

    function testSetManagementFees() public {
        vm.expectRevert();
        vault.setManagementFee(1000);
        vm.prank(governance);
        vault.setManagementFee(1000);
        assertEq(vault.managementFee(), 1000);
    }

    function testSetWithdrawalFees() public {
        vm.expectRevert();
        vault.setWithdrawalFee(1000);
        vm.prank(governance);
        vault.setWithdrawalFee(1000);
        assertEq(vault.withdrawalFee(), 1000);
    }

    function testSetDelegatorFactory() public {
        DelegatorFactory dFactory = new DelegatorFactory(address(vault));

        DelegatorFactory faultyFactory = new DelegatorFactory(address(alice));

        vm.expectRevert();
        vault.setDelegatorFactory(address(dFactory));

        vm.expectRevert();
        vm.prank(governance);
        vault.setDelegatorFactory(address(faultyFactory));

        vm.prank(governance);
        vault.setDelegatorFactory(address(dFactory));

        assertEq(address(dFactory), vault.delegatorFactory());
    }

    function testSetWithdrawalEscrow() public {
        // dummy vault
        UltraLRT dummyVault = new UltraLRT();
        dummyVault.initialize(governance, address(asset), address(vault.beacon()), "uLRT", "uLRT");
        WithdrawalEscrowV2 dummyEscrow = new WithdrawalEscrowV2(dummyVault);

        // replace with invalid vault one
        vm.expectRevert();
        vm.prank(governance);
        vault.setWithdrawalEscrow(dummyEscrow);

        // replace with address zero
        vm.expectRevert();
        vm.prank(governance);
        vault.setWithdrawalEscrow(WithdrawalEscrowV2(address(0)));

        // replace with valid ones

        dummyEscrow = new WithdrawalEscrowV2(vault);
        vm.prank(governance);
        vault.setWithdrawalEscrow(dummyEscrow);

        assertEq(address(dummyEscrow), address(vault.escrow()));

        // replace escrow having debt

        testDelegateToDelegator();
        // withdraw
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        dummyEscrow = new WithdrawalEscrowV2(vault);
        vm.expectRevert();
        vm.prank(governance);
        vault.setWithdrawalEscrow(dummyEscrow);
    }

    function testDelegatorWithdrawReq() public {
        testDelegateToDelegator();

        IDelegator d0 = vault.delegatorQueue(0);
        uint256 assets = d0.withdrawableAssets();
        // without harvester
        vm.expectRevert();
        vault.delegatorWithdrawRequest(d0, assets);

        // request more
        vm.expectRevert();
        vm.prank(governance);
        vault.delegatorWithdrawRequest(d0, assets + 100);

        // request full
        vm.prank(governance);
        vault.delegatorWithdrawRequest(d0, assets);

        assertApproxEqAbs(d0.withdrawableAssets(), 0, 100);
    }

    function testLiquidationRequest() public {
        testDelegateToDelegator();

        uint256 assets = vault.totalAssets();

        vm.expectRevert();
        vault.liquidationRequest(assets);

        vm.prank(governance);
        vault.liquidationRequest(assets);

        assertApproxEqAbs(vault.delegatorQueue(0).withdrawableAssets(), 0, 100);
        // do another liquidation request
        vm.prank(governance);
        vault.liquidationRequest(assets);
        assertApproxEqAbs(vault.delegatorQueue(0).withdrawableAssets(), 0, 100);
    }

    function testCollectDelegatorDebt() public {
        vm.expectRevert();
        vault.collectDelegatorDebt();

        testDelegateToDelegator();
        IDelegator d0 = vault.delegatorQueue(0);

        uint256 assets = _getAsset(address(d0), initAssets);

        assertApproxEqAbs(asset.balanceOf(address(d0)), assets, 100);

        vm.prank(governance);
        vault.collectDelegatorDebt();

        assertApproxEqAbs(asset.balanceOf(address(d0)), 0, 100);
    }

    function testDelegateToInactiveDelegator() public {
        testDeposit();

        uint256 assets = vault.vaultAssets();

        IDelegator d0 = vault.delegatorQueue(0);
        IDelegator d1 = vault.delegatorQueue(1);
        IDelegator d2 = vault.delegatorQueue(2);

        vm.prank(governance);
        vault.dropDelegator(address(d0));

        vm.prank(governance);
        vm.expectRevert();
        vault.delegateToDelegator(address(d0), assets);

        assertEq(address(d2), address(vault.delegatorQueue(0)));
        assertEq(address(d1), address(vault.delegatorQueue(1)));
        assertEq(address(0), address(vault.delegatorQueue(2)));
    }

    function testViewOnlyFunctions() public {
        assertEq(vault.maxDeposit(alice), type(uint128).max);
        assertEq(vault.decimals(), 26);
        assertEq(vault.initialSharesPerAsset(), 10 ** 8);
    }

    function testResolveDebt() public {
        testDelegateToDelegator();

        IDelegator delegator = vault.delegatorQueue(0);

        uint256 vaultShares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(vaultShares);
        // 99999999999999999997 asset
        // shares 96834476546864619822

        uint256 reqAssets = delegator.withdrawableAssets();

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(reqAssets), stEthStrategy.shares(address(delegator)));
        vm.prank(alice);
        uint256 blockNumber = block.number;

        vault.withdraw(assets, alice, alice);

        vm.prank(governance);
        vault.endEpoch();

        vm.prank(governance);
        vault.liquidationRequest(assets);

        // prep for withdraw
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNumber),
            strategies: strategies,
            shares: shares
        });
        vm.prank(governance);
        EigenDelegator(address(delegator)).completeWithdrawalRequest(params);

        // no assets
        vm.prank(governance);
        vm.expectRevert();
        vault.resolveDebt();

        vm.prank(governance);
        vault.collectDelegatorDebt();
        vm.prank(governance);
        vault.harvest();

        assertApproxEqAbs(asset.balanceOf(address(vault)), assets, 10_000);

        // not a harvester
        vm.expectRevert();
        vault.resolveDebt();

        vm.prank(governance);
        vault.resolveDebt();
        assertApproxEqAbs(asset.balanceOf(address(vault.escrow())), assets, 1000);
        //TODO: add error for it, should work but won't resolve
        vm.prank(governance);
        vault.resolveDebt();
    }

    function testInitializeVaultWithInvalidBeacon() public {
        UltraLRT dummyVault = new UltraLRT();

        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), address(this));
        // initialization data
        vm.expectRevert();
        dummyVault.initialize(governance, address(asset), address(beacon), "uLRT", "uLRT");
    }
}
