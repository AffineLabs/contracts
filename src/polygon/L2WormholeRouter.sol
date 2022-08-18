// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";
import { L2Vault } from "./L2Vault.sol";
import { WormholeRouter } from "../WormholeRouter.sol";
import { Constants } from "../Constants.sol";

contract L2WormholeRouter is WormholeRouter, Initializable {
    L2Vault vault;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L2Vault _vault,
        address _otherLayerRouter,
        uint16 _otherLayerChainId
    ) external initializer {
        wormhole = _wormhole;
        vault = _vault;
        governance = vault.governance();
        otherLayerRouter = _otherLayerRouter;
        otherLayerChainId = _otherLayerChainId;
    }

    function reportTransferredFund(uint256 amount) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L2_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    function requestFunds(uint256 amount) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L2_FUND_REQUEST, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    event TransferFromL1(uint256 amount);

    function receiveFunds(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L1_FUND_TRANSFER_REPORT);
        vault.bridgeEscrow().l2ClearFund(amount);
        emit TransferFromL1(amount);
    }

    function receiveTVL(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "Not a TVL message");
        L2Vault(address(vault)).receiveTVL(tvl, received);
    }
}
