// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "./mocks/index.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L2BridgeEscrow} from "../polygon/L2BridgeEscrow.sol";
import {L1BridgeEscrow} from "../ethereum/L1BridgeEscrow.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";

contract L2BridgeEscrowTest is TestPlus {
    using stdStorage for StdStorage;

    L2BridgeEscrow escrow;
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
        escrow = new L2BridgeEscrow(vault);

        // Set the bridgeEscrow
        vm.prank(governance);
        vault.setBridgeEscrow(escrow);
    }

    function testwithdraw() public {
        // Only the vault can send a certain amount to L1 (withdraw)
        vm.expectRevert("BE: Only vault");
        vm.prank(alice);
        escrow.withdraw(100);

        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to L1
        vm.prank(address(vault));
        escrow.withdraw(100);

        assertEq(asset.balanceOf(address(escrow)), 0);
    }

    function testclearFunds() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        changePrank(wormholeRouter);
        vm.expectCall(address(vault), abi.encodeCall(L2Vault.afterReceive, (100)));
        escrow.clearFunds(100, "");

        assertEq(asset.balanceOf(address(vault)), 100);
        // afterReceive was called on the vault
        assertEq(vault.canRequestFromL1(), true);
    }

    function testclearFundsInvariants() public {
        vm.expectRevert("BE: Only wormhole router");
        vm.prank(alice);
        escrow.clearFunds(100, "");

        // Give escrow some money less than the amount that the wormhole router expects
        // This means that the funds have not arrived from l1
        deal(address(asset), address(escrow), 100);

        changePrank(wormholeRouter);
        vm.expectRevert("BE: Funds not received");
        escrow.clearFunds(200, "");
    }
}

contract L1BridgeEscrowTest is TestPlus {
    L1BridgeEscrow escrow;
    MockL1Vault vault;
    address wormholeRouter;
    ERC20 asset;
    IRootChainManager manager;

    function setUp() public {
        // Not forking because getting a valid exitProof in clearFunds is tricky
        vault = deployL1Vault();
        asset = ERC20(vault.asset());
        wormholeRouter = vault.wormholeRouter();

        manager = IRootChainManager(address(asset)); // Any call to exit() will revert!
        escrow = new L1BridgeEscrow(vault, manager);

        // Set the bridgeEscrow
        vm.prank(governance);
        vault.setBridgeEscrow(escrow);
    }

    function testclearFunds() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        // Using an exitProof that is just empty bytes
        changePrank(wormholeRouter);
        vm.expectCall(address(vault), abi.encodeCall(L1Vault.afterReceive, ()));
        bytes memory exitProof;
        vm.mockCall(address(manager), abi.encodeCall(IRootChainManager.exit, (exitProof)), "");
        escrow.clearFunds(100, "");

        assertEq(asset.balanceOf(address(vault)), 100);
        // afterReceive was called on the vault
        assertTrue(vault.received());
    }

    function testclearFundsInvariants() public {
        vm.expectRevert("BE: Only wormhole router");
        vm.prank(alice);
        escrow.clearFunds(100, "");

        // Give escrow some money less than the amount that the wormhole router expects
        // This means that the funds have not arrived from l1
        deal(address(asset), address(escrow), 100);
        bytes memory exitProof;
        vm.mockCall(address(manager), abi.encodeCall(IRootChainManager.exit, (exitProof)), "");

        changePrank(wormholeRouter);
        vm.expectRevert("BE: Funds not received");
        escrow.clearFunds(200, "");
    }

    function testclearFundsWithBadProof() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        changePrank(wormholeRouter);
        vm.expectCall(address(vault), abi.encodeCall(L1Vault.afterReceive, ()));

        // We don't pass a valid exitProof, so we know rootchainmanager.exit() will fail
        // Even though that external call fails, the funds still get cleared
        escrow.clearFunds(100, "");

        assertEq(asset.balanceOf(address(vault)), 100);
        // afterReceive was called on the vault
        assertTrue(vault.received());
    }
}
