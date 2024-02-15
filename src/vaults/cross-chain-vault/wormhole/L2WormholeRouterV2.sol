// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {L2VaultBase} from "src/vaults/cross-chain-vault/baseVaults/L2VaultBase.sol";
import {WormholeRouterV2} from "./WormholeRouterV2.sol";
import {Constants} from "src/libs/Constants.sol";

contract L2WormholeRouterV2 is WormholeRouterV2 {
    // 
    function otherLayerWormholeId() public pure override returns (uint16) {
        return 10002;
    }

    constructor(L2VaultBase _vault, IWormhole _wormhole, address _gov) WormholeRouterV2(_vault, _wormhole) {
        governance = _gov;
    }

    function setVault(address _vault) external onlyGovernance {
        vault = L2VaultBase(_vault);
    }

    function setOtherLayerEmitter(address _otherLayerEmitter) external onlyGovernance {
        otherLayerEmitter = _otherLayerEmitter;
    }

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
    function receiveTVL(bytes calldata message, int64 _relayerFeePct ) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "WR: bad msg type");
        L2VaultBase(address(vault)).receiveTVL(tvl, received, _relayerFeePct);
    }
}