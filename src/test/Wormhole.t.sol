// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { L1WormholeRouter } from "../ethereum/L1WormholeRouter.sol";
import { L2WormholeRouter } from "../polygon/L2WormholeRouter.sol";
import { Constants } from "../Constants.sol";

contract MockWormhole is IWormhole {
    uint64 public emitterSequence;

    constructor() {}

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable override returns (uint64 sequence) {
        nonce;
        payload;
        consistencyLevel;
        emitterSequence += 1;
        sequence = emitterSequence;
    }

    function parseAndVerifyVM(bytes calldata encodedVM)
        external
        view
        returns (
            VM memory vm,
            bool valid,
            string memory reason
        )
    {
        valid = true;
        vm.payload = encodedVM;
        reason;
    }

    function nextSequence(address emitter) external view returns (uint64) {
        emitter;
        return emitterSequence;
    }
}

contract WormholeTest is TestPlus {
    L1Vault l1vault;
    L2Vault l2vault;
    L1WormholeRouter wormholeRouter;

    using stdStorage for StdStorage;

    function setUp() public {
        l1vault = Deploy.deployL1Vault();

        MockWormhole wormhole = new MockWormhole();
        wormholeRouter = l1vault.wormholeRouter();

        uint256 wormholeRouterSlot = stdstore.target(address(l1vault)).sig("wormholeRouter()").find();
        bytes32 wormholeRouterAddr = bytes32(uint256(uint160(address(wormholeRouter))));
        vm.store(address(l1vault), bytes32(wormholeRouterSlot), wormholeRouterAddr);

        wormholeRouter.initialize(wormhole, l1vault, address(0), 0);

        l2vault = Deploy.deployL2Vault();
    }

    function testMessagePass() public {
        bytes memory publishMessageData = abi.encodeWithSelector(
            IWormhole.publishMessage.selector,
            uint32(0),
            abi.encode(Constants.L1_TVL, uint256(0), false),
            4
        );

        // Grant rebalancer role to this address
        vm.startPrank(governance);
        l1vault.grantRole(l1vault.rebalancerRole(), address(this));
        vm.stopPrank();

        vm.expectCall(address(wormholeRouter.wormhole()), publishMessageData);
        l1vault.sendTVL();
        // TODO: assert that publish message was called wih certain arguments

        // TODO: call receive message with a given encodedTVL
        // TODO: assert that l2vault.L1TotalValue is the value that we expect
    }

    function testWormholeConfigUpdates() public {
        // update wormhole address
        changePrank(governance);
        wormholeRouter.setWormhole(IWormhole(address(this)));
        assertEq(address(wormholeRouter.wormhole()), address(this));

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        wormholeRouter.setWormhole(IWormhole(address(0)));

        // update consistencyLevel
        changePrank(governance);
        wormholeRouter.setConsistencyLevel(100);
        assertEq(wormholeRouter.consistencyLevel(), 100);

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        wormholeRouter.setConsistencyLevel(0);
    }
}

// This contract exists solely to test the internal view
contract MockRouter is L2WormholeRouter {
    function validateWormholeMessageEmitter(IWormhole.VM memory vm) public view {
        return _validateWormholeMessageEmitter(vm);
    }
}

contract L2WormholeRouterTest is TestPlus {
    using stdStorage for StdStorage;
    L2WormholeRouter router;
    L2Vault vault;

    function setUp() public {
        vm.createSelectFork("polygon", 31824532);
        vault = Deploy.deployL2Vault();
        router = vault.wormholeRouter();

        // See https://book.wormhole.com/reference/contracts.html for addresses
        router.initialize(IWormhole(0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7), vault, address(0), uint16(0));
    }

    function testTransferReport() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.reportTransferredFund(0);

        uint256 transferAmount = 100;
        bytes memory payload = abi.encode(Constants.L2_FUND_TRANSFER_REPORT, transferAmount);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.reportTransferredFund(transferAmount);
    }

    function testMessageValidation() public {
        MockRouter mockRouter = new MockRouter();
        uint16 emitter = uint16(1);
        address otherLayerRouter = makeAddr("otherLayerRouter");
        mockRouter.initialize(IWormhole(address(0)), vault, otherLayerRouter, emitter);

        IWormhole.VM memory vaa;
        vaa.emitterChainId = emitter;
        vaa.emitterAddress = bytes32(uint256(uint160(address(0))));
        vm.expectRevert("Wrong emitter address");
        mockRouter.validateWormholeMessageEmitter(vaa);

        IWormhole.VM memory vaa1;
        vaa1.emitterChainId = uint16(0);
        vaa1.emitterAddress = bytes32(uint256(uint160(otherLayerRouter)));
        emit log_named_bytes32("left padded addr: ", bytes32(uint256(uint160(makeAddr("otherLayerRouter")))));
        vm.expectRevert("Wrong emitter chain");
        mockRouter.validateWormholeMessageEmitter(vaa1);

        // This will work
        IWormhole.VM memory goodVaa;
        goodVaa.emitterChainId = emitter;
        goodVaa.emitterAddress = bytes32(uint256(uint160(otherLayerRouter)));
        mockRouter.validateWormholeMessageEmitter(goodVaa);
    }

    function testRequestFunds() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.requestFunds(0);

        uint256 requestAmount = 100;
        bytes memory payload = abi.encode(Constants.L2_FUND_REQUEST, requestAmount);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.requestFunds(requestAmount);
    }

    function testReceiveFunds() public {
        uint256 l1TransferAmount = 500;

        // Mock call to wormhole.parseAndVerifyVM()
        IWormhole.VM memory vaa;
        vaa.nonce = 20;
        vaa.payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, l1TransferAmount);

        bool valid = true;
        string memory reason = "";

        bytes memory wormholeReturnData = abi.encode(vaa, valid, reason);

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VA_FROM_L1_TRANSFER")),
            wormholeReturnData
        );

        // Make sure that bridgEscrow has funds to send to the vault
        deal(vault.asset(), address(vault.bridgeEscrow()), l1TransferAmount);

        // Make sure that L1TotalLockedValue is above amount being transferred to L2 (or else we get an underflow)
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("L1TotalLockedValue()").find()),
            bytes32(uint256(l1TransferAmount))
        );

        // You need the rebalancer role in the vault in order to call this function
        // Governance gets the rebalancer role
        vm.prank(governance);
        router.receiveFunds("VAA_FROM_L1_TRANSFER");

        // Nonce is updated
        assertEq(router.nextValidNonce(), vaa.nonce + 1);

        // Assert that funds get cleared
        assertEq(ERC20(vault.asset()).balanceOf(address(vault)), l1TransferAmount);
    }

    function testReceiveFundsInvariants() public {
        address rebalancer = governance;
        // You must have the rebalancer role to call receiveFunds
        vm.prank(alice);
        vm.expectRevert("Only Rebalancer");
        router.receiveFunds("VAA_FROM_L1_TRANSFER");

        // If wormhole says the vaa is bad, we revert
        // Mock call to wormhole.parseAndVerifyVM()
        IWormhole.VM memory vaa;
        bool valid = false;
        string memory reason = "Reason string from wormhole contract";

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VAA_FROM_L1_TRANSFER")),
            abi.encode(vaa, valid, reason)
        );

        vm.startPrank(rebalancer);
        vm.expectRevert(bytes(reason));
        router.receiveFunds("VAA_FROM_L1_TRANSFER");
        vm.clearMockedCalls();

        // If the nonce is old, we revert
        IWormhole.VM memory vaa2;
        vaa2.nonce = 10;

        // Make sure that L1TotalLockedValue is above amount being transferred to L2 (or else we get an underflow)
        vm.store(
            address(router),
            bytes32(stdstore.target(address(router)).sig("nextValidNonce()").find()),
            bytes32(uint256(11))
        );

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VAA_FROM_L1_TRANSFER")),
            abi.encode(vaa2, true, "")
        );

        vm.expectRevert("Old transaction");
        router.receiveFunds("VAA_FROM_L1_TRANSFER");
    }
}
