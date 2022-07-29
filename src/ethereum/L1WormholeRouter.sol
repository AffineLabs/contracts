// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

import { IWormhole } from "../interfaces/IWormhole.sol";
import { L1Vault } from "./L1Vault.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Constants } from "../Constants.sol";

contract L1WormholeRouter {
    L1Vault public vault;

    address public l2WormholeRouterAddress;
    uint16 public l2WormholeChainID;
    uint256 nextVaildNonce;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L1Vault _vault,
        address _l2WormholeRouterAddress,
        uint16 _l2WormholeChainID
    ) external {
        wormhole = _wormhole;
        vault = _vault;
        l2WormholeRouterAddress = _l2WormholeRouterAddress;
        l2WormholeChainID = _l2WormholeChainID;
    }

    /** WORMHOLE CONFIGURATION
     **************************************************************************/

    /// @notice The address of the core wormhole contract
    IWormhole public wormhole;
    /// @notice This is the number of blocks it takes to emit produce the VAA. See https://book.wormholenetwork.com/wormhole/4_vaa.html
    uint8 public consistencyLevel = 4;

    /// @notice Set the wormhole address
    function setWormhole(IWormhole _wormhole) external {
        require(msg.sender == vault.governance(), "Only Governance.");
        wormhole = _wormhole;
    }

    function setConsistencyLevel(uint8 _consistencyLevel) external {
        require(msg.sender == vault.governance(), "Only Governance.");
        consistencyLevel = _consistencyLevel;
    }

    function reportTVL(uint256 tvl, bool received) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_TVL, tvl, received);
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages
        // NOTE: 4 ETH blocks will take about 1 minute to propagate
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    function reportTransferredFund(uint256 amount) external {
        require(msg.sender == address(vault), "Only vault");
        bytes memory payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, amount);
        uint64 sequence = wormhole.nextSequence(address(this));

        wormhole.publishMessage(uint32(sequence), payload, consistencyLevel);
    }

    function validateWormholeMessageEmitter(IWormhole.VM memory vm) internal view {
        require(vm.emitterAddress == bytes32(uint256(uint160(l2WormholeRouterAddress))), "Wrong emitter address");
        require(vm.emitterChainId == l2WormholeChainID, "Message emitted from wrong chain");
    }

    function receiveFunds(bytes calldata message, bytes calldata data) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        validateWormholeMessageEmitter(vm);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_TRANSFER_REPORT);

        vault.bridgeEscrow().l1ClearFund(amount, data);
    }

    function receiveFundRequest(bytes calldata message) external {
        require(vault.hasRole(vault.rebalancerRole(), msg.sender), "Only Rebalancer");

        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        validateWormholeMessageEmitter(vm);
        require(vm.nonce >= nextVaildNonce, "Old transaction");
        nextVaildNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        require(msgType == Constants.L2_FUND_REQUEST);

        vault.processFundRequest(amount);
    }
}
