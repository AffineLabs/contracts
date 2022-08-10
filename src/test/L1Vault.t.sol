// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";
import { Constants } from "../Constants.sol";
import { L2Vault } from "../polygon/L2Vault.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { L1WormholeRouter } from "../ethereum/L1WormholeRouter.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { Deploy } from "./Deploy.sol";
import { EmergencyWithdrawalQueue } from "../polygon/EmergencyWithdrawalQueue.sol";
import { TestStrategy } from "./BaseVault.t.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";

contract L1VaultTest is TestPlus {
    using stdStorage for StdStorage;

    L1Vault vault;
    MockERC20 asset;

    function setUp() public {
        vm.createSelectFork("ethereum", 14971385);
        vault = Deploy.deployL1Vault();

        uint256 slot = stdstore.target(address(vault)).sig("wormhole()").find();
        bytes32 wormholeaddr = bytes32(uint256(uint160(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B)));
        vm.store(address(vault), bytes32(slot), wormholeaddr);

        slot = stdstore.target(address(vault)).sig("chainManager()").find();
        bytes32 chainmanageraddr = bytes32(uint256(uint160(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77)));
        vm.store(address(vault), bytes32(slot), chainmanageraddr);

        // setting bridge escrow addres to be non zero in order for deposit for to work
        slot = stdstore.target(address(vault)).sig("bridgeEscrow()").find();
        bytes32 bridgescrowaddr = bytes32(uint256(uint160(address(vault.wormholeRouter()))));
        vm.store(address(vault), bytes32(slot), bridgescrowaddr);

        // depositFor will fail unless mapToken has been called. Let's use real ETH USDC addr (it is mapped)
        // solhint-disable-next-line max-line-length
        // https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L169
        slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 assetAddr = bytes32(uint256(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)));
        vm.store(address(vault), bytes32(slot), assetAddr);
        asset = MockERC20(vault.asset());

        vault.wormholeRouter().initialize(vault.wormhole(), vault, address(0), 1);
    }

    function testSendTVL() public {
        // Grant rebalancer role to random user
        changePrank(governance);
        vault.grantRole(vault.rebalancerRole(), alice);

        // user can call sendTVL
        changePrank(alice);
        vault.sendTVL();
        assertTrue(vault.received() == false);
    }

    function testprocessFundRequest() public {
        // We need to either map the root token to the child token or
        // we need to use the correct already mapped addresses
        deal(address(asset), address(vault), 2e6, true);
        uint256 oldMsgCount = vault.wormhole().nextSequence(address(vault.wormholeRouter()));
        uint256 amount = 1e6;

        vm.prank(address(vault));
        asset.approve(vault.predicate(), amount);

        vm.prank(address(vault.wormholeRouter()));
        vault.processFundRequest(1e6);
        assertTrue(vault.wormhole().nextSequence(address(vault.wormholeRouter())) == oldMsgCount + 1);
    }

    function testafterReceive() public {
        BaseStrategy newStrategy1 = new TestStrategy(asset, vault);

        changePrank(governance);
        vault.addStrategy(newStrategy1, 1);

        deal(address(asset), address(vault), 10_000, true);

        changePrank(address(vault.bridgeEscrow()));
        vault.afterReceive();

        assertTrue(vault.received() == true);
        assertTrue(newStrategy1.balanceOfAsset() == 1);
    }

    function testLockedProfit() public {
        changePrank(governance);

        BaseStrategy newStrategy1 = new TestStrategy(asset, vault);
        vault.addStrategy(newStrategy1, 1000);

        deal(address(asset), address(newStrategy1), 1000, true);

        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = newStrategy1;
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        vault.harvest(strategies);
        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.maxLockedProfit(), 1000);
        assertEq(vault.vaultTVL(), 1000);
    }
}
