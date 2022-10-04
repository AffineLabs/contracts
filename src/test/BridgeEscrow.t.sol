// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "./mocks/index.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";

contract L2BridgeEscrowTest is TestPlus {
    using stdStorage for StdStorage;

    BridgeEscrow escrow;
    MockL2Vault vault;
    address wormholeRouter;
    ERC20 asset = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IRootChainManager manager = IRootChainManager(makeAddr("chain_manager"));

    function setUp() public {
        // Forking here because a mock ERC20 will not have the `withdraw` function
        vm.createSelectFork("polygon", 31_824_532);
        vault = deployL2Vault();
        // Set the asset
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(asset))))
        );

        // So we can call "afterReceive" and decrement the total locked value
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(200))
        );

        wormholeRouter = vault.wormholeRouter();
        escrow = new BridgeEscrow(address(vault), manager);

        // Set the bridgeEscrow
        vault.setBridgeEscrow(escrow);
    }

    function testL2Withdraw() public {
        // Only the vault can send a certain amount to L1 (withdraw)
        vm.expectRevert("Only vault");
        vm.prank(alice);
        escrow.l2Withdraw(100);

        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to L1
        vm.prank(address(vault));
        escrow.l2Withdraw(100);

        assertEq(asset.balanceOf(address(escrow)), 0);
    }

    function testL2ClearFund() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        changePrank(wormholeRouter);
        vm.expectCall(address(vault), abi.encodeCall(L2Vault.afterReceive, (100)));
        escrow.l2ClearFund(100);

        assertEq(asset.balanceOf(address(vault)), 100);
        // afterReceive was called on the vault
        assertEq(vault.canRequestFromL1(), true);
    }

    function testL2ClearFundInvariants() public {
        vm.expectRevert("Only wormhole router");
        vm.prank(alice);
        escrow.l2ClearFund(100);

        // Give escrow some money less than the amount that the wormhole router expects
        // This means that the funds have not arrived from l1
        deal(address(asset), address(escrow), 100);

        changePrank(wormholeRouter);
        vm.expectRevert("Funds not received");
        escrow.l2ClearFund(200);
    }
}

contract L1BridgeEscrowTest is TestPlus {
    BridgeEscrow escrow;
    MockL1Vault vault;
    address wormholeRouter;
    ERC20 asset;
    IRootChainManager manager = IRootChainManager(makeAddr("chain_manager"));

    function setUp() public {
        // Not forking because getting a valid exitProof in l1ClearFund is tricky
        vault = deployL1Vault();
        asset = ERC20(vault.asset());
        wormholeRouter = vault.wormholeRouter();

        escrow = new BridgeEscrow(address(vault), manager);

        // Set the bridgeEscrow
        vault.setBridgeEscrow(escrow);
    }

    function testL1ClearFund() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        // Using an exitProof that is just empty bytes
        changePrank(wormholeRouter);
        vm.expectCall(address(vault), abi.encodeCall(L1Vault.afterReceive, ()));
        bytes memory exitProof;
        vm.mockCall(address(manager), abi.encodeCall(IRootChainManager.exit, (exitProof)), "");
        escrow.l1ClearFund(100, "");

        assertEq(asset.balanceOf(address(vault)), 100);
        // afterReceive was called on the vault
        assertTrue(vault.received());
    }

    function testL1ClearFundInvariants() public {
        vm.expectRevert("Only wormhole router");
        vm.prank(alice);
        escrow.l1ClearFund(100, "");

        // Give escrow some money less than the amount that the wormhole router expects
        // This means that the funds have not arrived from l1
        deal(address(asset), address(escrow), 100);
        bytes memory exitProof;
        vm.mockCall(address(manager), abi.encodeCall(IRootChainManager.exit, (exitProof)), "");

        changePrank(wormholeRouter);
        vm.expectRevert("Funds not received");
        escrow.l1ClearFund(200, "");
    }
}
