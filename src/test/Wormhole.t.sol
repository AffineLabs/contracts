// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";

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

contract WormholeTest is DSTestPlus {
    L1Vault l1vault;
    L2Vault l2vault;

    using stdStorage for StdStorage;

    function setUp() public {
        l1vault = Deploy.deployL1Vault();

        MockWormhole wormhole = new MockWormhole();
        uint256 slot = stdstore.target(address(l1vault)).sig("wormhole()").find();
        bytes32 wormholeAddr = bytes32(uint256(uint160(address(wormhole))));
        hevm.store(address(l1vault), bytes32(slot), wormholeAddr);

        l2vault = Deploy.deployL2Vault();
    }

    function testMessagePass() public {
        bytes memory publishMessageData = abi.encodeWithSelector(
            IWormhole.publishMessage.selector,
            uint32(0),
            abi.encode(0, false),
            4
        );
        hevm.expectCall(address(l1vault.wormhole()), publishMessageData);
        l1vault.sendTVL();
        // TODO: assert that publish message was called wih certain arguments

        // TODO: call receive message with a given encodedTVL
        // TODO: assert that l2vault.L1TotalValue is the value that we expect
    }
}
