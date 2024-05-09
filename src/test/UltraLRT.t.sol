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

import {UltraLRT, Math, DelegatorBeacon} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {AffineDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/AffineDelegator.sol";
import {console2} from "forge-std/console2.sol";

contract TmpDelegator is AffineDelegator {
    function version() public pure returns (uint256) {
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
        vm.createSelectFork("ethereum", 19_770_000);
        // ultra LRT impl
        UltraLRT impl = new UltraLRT();
        // delegator implementation
        AffineDelegator delegatorImpl = new AffineDelegator();
        // initialization data
        bytes memory initData =
            abi.encodeCall(UltraLRT.initialize, (governance, address(asset), address(delegatorImpl), "uLRT", "uLRT"));
        // proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        // upgradeable vault
        vault = UltraLRT(address(proxy));

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

    function testCreateDelegator() public {
        testDeposit();
        uint256 oldDelegatorCount = vault.delegatorCount();

        vm.prank(governance);
        vault.createDelegator(operator);
        assertEq(vault.delegatorCount(), oldDelegatorCount + 1);
    }

    function testDelegateToDelegator() public {
        testDeposit();
        IDelegator delegator = vault.delegatorQueue(0);
        console2.log("delegator %s", address(delegator));

        uint256 assets = vault.totalAssets();
        vm.prank(governance);
        vault.delegateToDelegator(address(delegator), assets);

        assertApproxEqAbs(vault.totalAssets(), assets, 100);

        assertApproxEqAbs(delegator.totalLockedValue(), assets, 100);

        // can withdraw should be false
        assertTrue(!vault.canWithdraw(100_000_000));
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
        AffineDelegator(address(delegator)).completeWithdrawalRequest(params);

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
        asset.approve(address(vault), stEth);

        vm.prank(alice);
        vault.deposit(stEth, alice);

        // unpause
        vm.prank(governance);
        vault.pauseDeposit();

        vm.startPrank(alice);
        vm.expectRevert();
        vault.deposit(stEth, alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
    }

    function testHarvest() public {
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

        assertApproxEqAbs(vault.totalAssets(), stEth, 100);

        vm.warp(block.timestamp + 24 * 3600);
        assertApproxEqAbs(vault.totalAssets(), stEth * 3, 100);
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
        AffineDelegator(address(delegator)).completeWithdrawalRequest(params);

        vm.prank(governance);
        vault.collectDelegatorDebt();
        vm.prank(governance);
        vault.harvest();

        vm.prank(governance);
        vault.resolveDebt();

        escrow.redeem(alice, 0);
        assertApproxEqAbs(asset.balanceOf(address(alice)), assets, 100);
    }
}
