// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import { IWormhole } from "../interfaces/IWormhole.sol";
import { L2Vault } from "./L2Vault.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Constants } from "../Constants.sol";

contract L2WormholeRouter {
    L2Vault public vault;

    address public l1WormholeRouterAddress;
    uint16 public l1WormholeChainID;

    uint256 nextVaildNonce;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L2Vault _vault,
        address _l1WormholeRouterAddress,
        uint16 _l1WormholeChainID
    ) external {
        wormhole = _wormhole;
        vault = _vault;
        l1WormholeRouterAddress = _l1WormholeRouterAddress;
        l1WormholeChainID = _l1WormholeChainID;
    }

    /** WORMHOLE CONFIGURATION
     **************************************************************************/

    /// @notice The address of the core wormhole contract
    IWormhole public wormhole;
    /// @notice This is the number of blocks it takes to emit produce the VAA. See https://book.wormholenetwork.com/wormhole/4_vaa.html
    uint8 public consistencyLevel = 4;

    /// @notice Set the wormhole address
    function setWormhole(IWormhole _wormhole) external {
        require(msg.sender == vault.governance(), "Only governance");
        wormhole = _wormhole;
    }

    function setConsistencyLevel(uint8 _consistencyLevel) external {
        require(msg.sender == vault.governance(), "Only governance");
        consistencyLevel = _consistencyLevel;
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

    function validateWormholeMessageEmitter(IWormhole.VM memory vm) internal view {
        require(vm.emitterAddress == bytes32(uint256(uint160(l1WormholeRouterAddress))), "Wrong emitter address");
        require(vm.emitterChainId == l1WormholeChainID, "Message emitted from wrong chain");
    }

    function receiveFunds(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        validateWormholeMessageEmitter(vm);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L1_FUND_TRANSFER_REPORT);
        vault.bridgeEscrow().l2ClearFund(amount);
    }

    function receiveTVL(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        validateWormholeMessageEmitter(vm);
        require(vm.nonce >= nextVaildNonce, "Old TVL");
        nextVaildNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "Not a TVL message");
        vault.receiveTVL(tvl, received);
    }
}
