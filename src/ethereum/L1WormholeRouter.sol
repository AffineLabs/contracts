// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {L1Vault} from "./L1Vault.sol";
import {WormholeRouter} from "../WormholeRouter.sol";
import {Constants} from "../libs/Constants.sol";

contract L1WormholeRouter is WormholeRouter {
    function otherLayerWormholeId() public pure override returns (uint16) {
        return 5;
    }

    constructor(L1Vault _vault, IWormhole _wormhole) WormholeRouter(_vault, _wormhole) {}

    /**
     * @notice Send tvl message to L2.
     * @param tvl The current tvl of L1Vault
     * @param received True if L1Vault received latest transfer from L2.
     */
    function reportTVL(uint256 tvl, bool received) external payable {
        require(msg.sender == address(vault), "WR: only vault");
        bytes memory payload = abi.encode(Constants.L1_TVL, tvl, received);
        // We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    /// @notice Let L2 know that is should receive `amount` of `asset`.
    function reportFundTransfer(uint256 amount) external payable {
        require(msg.sender == address(vault), "WR: only vault");
        bytes memory payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));
        wormhole.publishMessage{value: msg.value}(uint32(sequence), payload, consistencyLevel);
    }

    /**
     * @notice Receive message confirming transfer from L2Vault.
     * @param message The wormhole VAA.
     * @param data The exitProof for the Polygon Pos Bridge RootChainManager.
     */
    function receiveFunds(bytes calldata message, bytes calldata data) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_TRANSFER_REPORT, "WR: bad msg type");

        vault.bridgeEscrow().clearFunds(amount, data);
    }

    /// @notice Receive `message` with a request for funds from L2.
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
