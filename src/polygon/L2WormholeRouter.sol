// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import { Initializable } from "../Initializable.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IStaging } from "../interfaces/IStaging.sol";
import { IL2Vault } from "../interfaces/IVault.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Constants } from "../Constants.sol";

contract L2WormholeRotuer is Initializable {
    IWormhole public wormhole;
    IL2Vault public vault;
    IStaging public staging;

    uint256 nextVaildNonce;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        IL2Vault _vault
    ) external initializer() {
        wormhole = _wormhole;
        vault = _vault;
        staging = IStaging(vault.staging());
    }

    function reportTrasferredFund(uint256 amount) external {
        bytes memory payload = abi.encodePacked(Constants.L2_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function requestFunds(uint256 amount) external {
        bytes memory payload = abi.encodePacked(Constants.L2_FUND_REQUEST, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function receiveFunds(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        // TODO: check chain ID, emitter address
        // Get amount and nonce
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L1_FUND_TRANSFER_REPORT);
        staging.l2ClearFund(amount);
    }

    function receiveTVL(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        require(vm.nonce >= nextVaildNonce, "Old TVL");
        nextVaildNonce = vm.nonce + 1;
        // TODO: check chain ID, emitter address
        // Get tvl from payload
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "Not a TVL message");
        vault.receiveTVL(tvl, received);
    }
}