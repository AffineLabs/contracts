// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import { IWormhole } from "../interfaces/IWormhole.sol";
import { L1Vault } from "./L1Vault.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Constants } from "../Constants.sol";

contract L1WormholeRouter {
    IWormhole public wormhole;
    L1Vault public vault;

    uint256 nextVaildNonce;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L1Vault _vault
    ) external {
        wormhole = _wormhole;
        vault = _vault;
    }

    function reportTVL(uint256 tvl, bool received) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encodePacked(Constants.L1_TVL, tvl, received);
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages

        // NOTE: 4 ETH blocks will take about 1 minute to propagate
        // TODO: make wormhole address, consistencyLevel configurable
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function reportTransferredFund(uint256 amount) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encodePacked(Constants.L1_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function receiveFunds(bytes calldata message, bytes calldata data) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        // TODO: check chain ID, emitter address
        // Get amount and nonce
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_TRANSFER_REPORT);

        vault.bridgeEscrow().l1ClearFund(amount, data);
    }

    function receiveFundRequest(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        // TODO: check chain ID, emitter address
        // Get amount and nonce
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_REQUEST);

        vault.processFundRequest(amount);
    }
}