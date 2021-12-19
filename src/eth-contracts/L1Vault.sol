// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { BaseVault } from "../BaseVault.sol";
import { L1BalancableVault } from "./L1BalancableVault.sol";

contract L1Vault is BaseVault, L1BalancableVault {
    constructor(
        address governance_,
        address token_,
        address wormhole_,
        address _l1ContractRegistryAddress
    ) BaseVault(governance_, token_, wormhole_) L1BalancableVault(_l1ContractRegistryAddress) {}

    function sendTVL() external {
        uint256 tvl = vaultTVL();
        bytes memory payload = abi.encodePacked(tvl, block.number);

        uint64 sequence = wormhole.nextSequence(address(this));
        // NOTE: We use the current tx count (to wormhole) of this contract
        // as a nonce when publishing messages
        // This casting is fine so long as we send less than 2 ** 32 - 1 (~ 4 billion) messages

        // NOTE: 4 ETH blocks will take about 1 minute to propagate
        // TODO: make wormhole address, consistencyLevel configurable
        wormhole.publishMessage(uint32(sequence), payload, 4);
    }
}
