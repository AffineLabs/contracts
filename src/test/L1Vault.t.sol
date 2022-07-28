// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

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
        asset = MockERC20(vault.asset());
        uint256 slot = stdstore.target(address(vault)).sig("wormhole()").find();
        bytes32 wormholeaddr = bytes32(uint256(uint160(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B)));
        vm.store(address(vault), bytes32(slot), wormholeaddr);
        slot = stdstore.target(address(vault)).sig("chainManager()").find();
        bytes32 chainmanageraddr = bytes32(uint256(uint160(0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74)));
        vm.store(address(vault), bytes32(slot), chainmanageraddr);
        vault.wormholeRouter().initialize(vault.wormhole(), vault, address(0), 1);
        // setting bridge escrow addres to be non zero in order for deposit for to work
        slot = stdstore.target(address(vault)).sig("bridgeEscrow()").find();
        bytes32 bridgescrowaddr = bytes32(uint256(uint160(address(vault.wormholeRouter()))));
        vm.store(address(vault), bytes32(slot), bridgescrowaddr);
    }

    function testSendTVL() public {
        // Grant rebalancer role to this address
        vault.grantRole(vault.rebalancerRole(), address(this));
        vault.sendTVL();
        assertTrue(vault.received() == false);
    }

    function testprocessFundRequest() public {
        asset.mint(address(vault), 2e6);
        emit log_named_address("Escrow addr: ", address(vault.bridgeEscrow()));
        uint256 old_msg_count = vault.wormhole().nextSequence(address(vault.wormholeRouter()));
        uint256 amount = 1e6;
        vm.mockCall(
            address(vault.chainManager()),
            abi.encodeWithSelector(
                IRootChainManager.depositFor.selector,
                address(vault.bridgeEscrow()),
                address(asset),
                abi.encodePacked(amount)
            ),
            abi.encode(0)
        );
        vm.prank(address(vault.wormholeRouter()));
        vault.processFundRequest(1e6);
        assertTrue(vault.wormhole().nextSequence(address(vault.wormholeRouter())) > old_msg_count);
    }

    function testafterReceive() public {
        BaseStrategy newStrategy1 = new TestStrategy(asset, vault);
        vault.addStrategy(newStrategy1, 1);
        asset.mint(address(vault), 10000);
        vm.prank(address(0));
        vault.afterReceive();
        assertTrue(vault.received() == true);
        assertTrue(newStrategy1.balanceOfAsset() == 1);
    }
}
