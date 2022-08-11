// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { L1WormholeRouter } from "../ethereum/L1WormholeRouter.sol";
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
        wormholeRouter = new L1WormholeRouter();

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
