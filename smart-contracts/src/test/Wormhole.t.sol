// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20User } from "./ERC20User.sol";
import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { L1Vault } from "../eth-contracts/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";

contract MockWormhole is IWormhole {
    uint64 emitterSequence;

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

contract WormholeTest is DSTest {
    L1Vault l1vault;
    L2Vault l2vault;
    MockERC20 token;
    ERC20User user;
    MockWormhole wormhole;

    function setUp() public {
        token = new MockERC20("Mock", "MT", 18);

        wormhole = new MockWormhole();
        l1vault = new L1Vault(address(0), address(token), address(wormhole), address(0));
        l2vault = new L2Vault(address(0), address(token), 1, 1, address(wormhole), address(0));

        user = new ERC20User(token);
    }

    function testMessagePass() public {
        l1vault.sendTVL();
        // TODO: assert that publish message was called wih certain arguments

        // TODO: call receive message with a given encodedTVL
        // TODO: assert that l2vault.L1TotalValue is the value that we expect
    }
}
