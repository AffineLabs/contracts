// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { MockERC20 } from "./MockERC20.sol";
import { ERC20User } from "./ERC20User.sol";
import { L2Vault } from "../polygon-contracts/L2Vault.sol";
import { L1Vault } from "../eth-contracts/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { Create2Deployer } from "./Create2Deployer.sol";

contract MockWormhole is IWormhole {
    uint64 public emitterSequence;

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
    Create2Deployer create2Deployer;

    function setUp() public {
        token = new MockERC20("Mock", "MT", 18);
        wormhole = new MockWormhole();
        create2Deployer = new Create2Deployer();
        l1vault = new L1Vault();
        l1vault.initialize(
            address(0), // governance
            token, // token
            wormhole, // wormhole
            create2Deployer, // create2deployer (must be real address)
            IRootChainManager(address(0)), // chain manager
            address(0) // predicate
        );
        // The whole point of the create2deployer is so that the staging contracts get the same address
        // But since we're using one chain we actually can't use the same create2deployer a second time!
        l2vault = new L2Vault();
        l2vault.initialize(address(0), token, wormhole, new Create2Deployer(), 1, 1, address(0), 0);
        user = new ERC20User(token);
    }

    function testMessagePass() public {
        l1vault.sendTVL();
        assertEq(wormhole.emitterSequence(), 1);
        // TODO: assert that publish message was called wih certain arguments

        // TODO: call receive message with a given encodedTVL
        // TODO: assert that l2vault.L1TotalValue is the value that we expect
    }
}
