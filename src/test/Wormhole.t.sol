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
        
        uint256 wormholeSlot = stdstore.target(address(wormholeRouter)).sig("wormhole()").find();
        bytes32 wormholeAddr = bytes32(uint256(uint160(address(wormhole))));
        vm.store(address(wormholeRouter), bytes32(wormholeSlot), wormholeAddr);

        wormholeRouter.initialize(wormhole, l1vault);     

        l2vault = Deploy.deployL2Vault();
    }

    function testMessagePass() public {
        bytes memory publishMessageData = abi.encodeWithSelector(
            IWormhole.publishMessage.selector,
            uint32(0),
            abi.encodePacked(Constants.L1_TVL, uint256(0), false),
            4
        );
        vm.expectCall(address(wormholeRouter.wormhole()), publishMessageData);
        l1vault.sendTVL();
        // TODO: assert that publish message was called wih certain arguments

        // TODO: call receive message with a given encodedTVL
        // TODO: assert that l2vault.L1TotalValue is the value that we expect
    }
}
