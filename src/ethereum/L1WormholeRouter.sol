// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {L1Vault} from "./L1Vault.sol";
import {WormholeRouter} from "../WormholeRouter.sol";
import {Constants} from "../Constants.sol";

contract L1WormholeRouter is WormholeRouter {
    L1Vault vault;

    constructor(L1Vault _vault, IWormhole _wormhole, uint16 _otherLayerWormholeChainId)
        WormholeRouter(_wormhole, _otherLayerWormholeChainId)
    {
        vault = _vault;
        governance = vault.governance();
    }

    function reportTVL(uint256 tvl, bool received) external payable {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_TVL, tvl, received);
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    function reportTransferredFund(uint256 amount) external payable {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    event TransferFromL2(uint256 amount);

    function receiveFunds(bytes calldata message, bytes calldata data) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_TRANSFER_REPORT, "WR: bad msg type");

        vault.bridgeEscrow().l1ClearFund(amount, data);
        emit TransferFromL2(amount);
    }

    event TransferToL2(uint256 amount);

    function receiveFundRequest(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_REQUEST, "WR: bad msg type");

        L1Vault(address(vault)).processFundRequest(amount);
    }
}
