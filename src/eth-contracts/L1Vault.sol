// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IWormhole } from "../interfaces/IWormhole.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IStaging } from "../interfaces/IStaging.sol";
import { BaseVault } from "../BaseVault.sol";

contract L1Vault is BaseVault {
    /////// Cross chain rebalancing
    bool public received;
    IRootChainManager public chainManager;
    // `predicate` will take tokens from vault when depositFor is called on the RootChainManager
    // solhint-disable-next-line max-line-length
    // https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L267
    address public predicate;

    constructor(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        ICreate2Deployer create2Deployer,
        IRootChainManager _chainManager,
        address _predicate
    ) BaseVault(_governance, _token, _wormhole, create2Deployer) {
        chainManager = _chainManager;
        IStaging(staging).initializeL1(_chainManager);
        predicate = _predicate;
    }

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
        uint256 amountRequested = abi.decode(vm.payload, (uint256));
        _liquidate(amountRequested);
        uint256 amountToSend = Math.min(token.balanceOf(address(this)), amountRequested);
        _transferFundsToL2(amountToSend);
    }

    // Send `token` to L2 staging via polygon bridge
    function _transferFundsToL2(uint256 amount) internal {
        token.approve(predicate, amount);
        chainManager.depositFor(staging, address(token), abi.encodePacked(amount));

        // Let L2 know how much money we sent
        uint64 sequence = wormhole.nextSequence(address(this));
        bytes memory payload = abi.encodePacked(amount);
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }

    function afterReceive() external {
        require(msg.sender == staging, "Only L1 staging.");
        received = true;
    }
}
