// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

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
}
