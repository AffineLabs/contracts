// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {L2Vault} from "./L2Vault.sol";
import {WormholeRouter} from "../WormholeRouter.sol";
import {Constants} from "../libs/Constants.sol";

contract L2WormholeRouter is WormholeRouter {
    function otherLayerWormholeId() public pure override returns (uint16) {
        return 2;
    }

    constructor(L2Vault _vault, IWormhole _wormhole) WormholeRouter(_vault, _wormhole) {}

    /// @notice Let L1 know that is should receive `amount` of `asset`.
    function reportFundTransfer(uint256 amount) external payable {
        require(msg.sender == address(vault), "WR: Only vault");
        bytes memory payload = abi.encode(Constants.L2_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    /// @notice Request of `amount` of `asset` from L1Vault.
    function requestFunds(uint256 amount) external payable {
        require(msg.sender == address(vault), "WR: Only vault");
        bytes memory payload = abi.encode(Constants.L2_FUND_REQUEST, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    /// @notice Receive `message` confirming transfer from L1Vault.
    function receiveFunds(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L1_FUND_TRANSFER_REPORT, "WR: bad msg type");
        vault.bridgeEscrow().clearFunds(amount, "");
    }

    /// @notice Receive `message` with L1Vault's tvl data.
    function receiveTVL(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "WR: bad msg type");
        L2Vault(address(vault)).receiveTVL(tvl, received);
    }
}
