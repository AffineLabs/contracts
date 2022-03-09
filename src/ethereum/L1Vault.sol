// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IStaging } from "../interfaces/IStaging.sol";
import { BaseVault } from "../BaseVault.sol";
import { Constants } from "../Constants.sol";

contract L1Vault is PausableUpgradeable, UUPSUpgradeable, BaseVault {
    /////// Cross chain rebalancing
    bool public received;
    IRootChainManager public chainManager;
    // `predicate` will take tokens from vault when depositFor is called on the RootChainManager
    // solhint-disable-next-line max-line-length
    // https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L267
    address public predicate;

    constructor() {}

    function initialize(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer,
        IRootChainManager _chainManager,
        address _predicate
    ) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        BaseVault.init(_governance, _token, _wormhole, create2Deployer);
        chainManager = _chainManager;
        IStaging(staging).initializeL1(chainManager);
        predicate = _predicate;
    }

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return Context._msgSender();
    }

    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        return Context._msgData();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    function sendTVL() external {
        uint256 tvl = vaultTVL();
        // You can't decode an int with a bool if they are encoded with encodePacked
        bytes memory payload = abi.encode(tvl, received);

        uint64 sequence = wormhole.nextSequence(address(this));
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages

        // NOTE: 4 ETH blocks will take about 1 minute to propagate
        // TODO: make wormhole address, consistencyLevel configurable
        wormhole.publishMessage(uint32(sequence), payload, 4);

        // If received == true then the l2-l1 bridge gets unlocked upon message reception in l2
        // Resetting this to false since we haven't received any new transfers from L2 yet
        if (received) received = false;
    }

    // Process a request for funds from L2 vault
    function receiveMessage(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);

        // TODO: check chain ID, emitter address

        // get amount requested
        (bytes32 msgType, uint256 amountRequested) = abi.decode(vm.payload, (bytes32, uint256));
        _liquidate(amountRequested);
        uint256 amountToSend = Math.min(token.balanceOf(address(this)), amountRequested);
        if (msgType == Constants.NORMAL_REBALANCE) {
            _transferFundsToL2(amountToSend);
        } else {
            _transferFundsToL2Emergency(amountToSend);
        }
    }

    // Send `token` to L2 staging via polygon bridge in emergency
    function _transferFundsToL2Emergency(uint256 amount) internal {
        token.approve(predicate, amount);
        chainManager.depositFor(staging, address(token), abi.encodePacked(amount));

        // Let L2 know how much money we sent
        uint64 sequence = wormhole.nextSequence(address(this));
        bytes memory payload = abi.encodePacked(Constants.EMERGENCY_REBALANCE, amount);
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    // Send `token` to L2 staging via polygon bridge
    function _transferFundsToL2(uint256 amount) internal {
        token.approve(predicate, amount);
        chainManager.depositFor(staging, address(token), abi.encodePacked(amount));

        // Let L2 know how much money we sent
        uint64 sequence = wormhole.nextSequence(address(this));
        bytes memory payload = abi.encodePacked(Constants.NORMAL_REBALANCE, amount);
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function afterReceive() external {
        require(msg.sender == staging, "Only L1 staging.");
        received = true;
    }
}