// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {BridgeEscrow} from "../BridgeEscrow.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";

contract BridgeEscrowTest is TestPlus {
    BridgeEscrow escrow;
    address deployer = makeAddr("deployer");
    address owner = makeAddr("owner");

    function setUp() public {
        vm.prank(deployer);
        escrow = new BridgeEscrow(owner);
    }

    function testDeploy() public {
        assertEq(owner, escrow.owner());
    }

    function testInitialize() public {
        // Only the owner can init
        vm.expectRevert("ONLY_OWNER");
        escrow.initialize(address(0), address(0), ERC20(address(0)), IRootChainManager(address(0)));

        // Can init
        address vault = makeAddr("vault");
        address wormholeRouter = makeAddr("wormhole_router");
        ERC20 asset = ERC20(makeAddr("asset"));
        IRootChainManager manager = IRootChainManager(makeAddr("chain_manager"));
        vm.prank(owner);
        escrow.initialize(vault, wormholeRouter, asset, manager);

        assertEq(escrow.vault(), vault);
        assertEq(escrow.wormholeRouter(), wormholeRouter);
        assertEq(address(escrow.token()), address(asset));
        assertEq(address(escrow.rootChainManager()), address(manager));

        // Can only initialize once
        vm.prank(owner);
        vm.expectRevert("INIT_DONE");
        escrow.initialize(vault, wormholeRouter, asset, manager);
    }
}

contract DummyL2Vault {
    uint256 public x;

    constructor() {}

    function afterReceive(uint256 amount) public {
        amount;
        x = 2;
    }
}

contract L2BridgeEscrowTest is TestPlus {
    BridgeEscrow escrow;
    address vault;
    address wormholeRouter = makeAddr("wormhole_router");
    ERC20 asset = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IRootChainManager manager = IRootChainManager(makeAddr("chain_manager"));

    function setUp() public {
        // Forking here because a mock ERC20 will not have the `withdraw` function
        vm.createSelectFork("polygon", 31_824_532);
        vault = address(new DummyL2Vault());
        escrow = new BridgeEscrow(address(this));
        escrow.initialize(vault, wormholeRouter, asset, manager);
    }

    function testL2Withdraw() public {
        // Only the vault can send a certain amount to L1 (withdraw)
        vm.expectRevert("Only vault");
        vm.prank(alice);
        escrow.l2Withdraw(100);

        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to L1
        vm.prank(vault);
        escrow.l2Withdraw(100);

        assertEq(asset.balanceOf(address(escrow)), 0);
    }

    function testL2ClearFund() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        changePrank(wormholeRouter);
        vm.expectCall(vault, abi.encodeCall(DummyL2Vault.afterReceive, (100)));
        escrow.l2ClearFund(100);

        assertEq(asset.balanceOf(vault), 100);
        // afterReceive was called on the vault
        assertEq(DummyL2Vault(vault).x(), 2);
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

contract DummyL1Vault {
    uint256 public x;

    constructor() {}

    function afterReceive() public {
        x = 1;
    }
}

contract L1BridgeEscrowTest is TestPlus {
    BridgeEscrow escrow;
    address vault;
    address wormholeRouter = makeAddr("wormhole_router");
    ERC20 asset;
    IRootChainManager manager = IRootChainManager(makeAddr("chain_manager"));

    function setUp() public {
        // Not forking because getting a valid exitProof in l1ClearFund is tricky
        vault = address(new DummyL1Vault());
        asset = new MockERC20("Mock Token", "MT", 18);
        escrow = new BridgeEscrow(address(this));
        escrow.initialize(vault, wormholeRouter, asset, manager);
    }

    function testL1ClearFund() public {
        // Give escrow some money
        deal(address(asset), address(escrow), 100);

        // Send money to vault (clear funds)
        // Using an exitProof that is just empty bytes
        changePrank(wormholeRouter);
        vm.expectCall(vault, abi.encodeCall(DummyL1Vault.afterReceive, ()));
        bytes memory exitProof;
        vm.mockCall(address(manager), abi.encodeCall(IRootChainManager.exit, (exitProof)), "");
        escrow.l1ClearFund(100, "");

        assertEq(asset.balanceOf(vault), 100);
        // afterReceive was called on the vault
        assertEq(DummyL1Vault(vault).x(), 1);
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
