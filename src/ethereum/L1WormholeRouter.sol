// SPDX-License-Identifier:MIT
pragma solidity ^0.8.16;

import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";
import { L1Vault } from "./L1Vault.sol";
import { WormholeRouter } from "../WormholeRouter.sol";
import { Constants } from "../Constants.sol";

contract L1WormholeRouter is WormholeRouter, Initializable {
    L1Vault vault;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L1Vault _vault,
        address _otherLayerRouter,
        uint16 _otherLayerChainId
    ) external initializer {
        wormhole = _wormhole;
        vault = _vault;
        governance = vault.governance();
        otherLayerRouter = _otherLayerRouter;
        otherLayerChainId = _otherLayerChainId;
    }

    function reportTVL(uint256 tvl, bool received) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_TVL, tvl, received);
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    function reportTransferredFund(uint256 amount) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    event TransferFromL2(uint256 amount);

    function receiveFunds(bytes calldata message, bytes calldata data) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_TRANSFER_REPORT);

        vault.bridgeEscrow().l1ClearFund(amount, data);
        emit TransferFromL2(amount);
    }

    event TransferToL2(uint256 amount);

    function receiveFundRequest(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_REQUEST);

        L1Vault(address(vault)).processFundRequest(amount);
    }
}
