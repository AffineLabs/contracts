// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {L2WormholeRouter} from "./L2WormholeRouter.sol";
import {Constants} from "src/libs/Constants.sol";

contract L2WormholeRouterV2 is L2WormholeRouter {

    function otherLayerWormholeId() public pure override returns (uint16) {
        return 10002;
    }

    constructor(L2Vault _vault, IWormhole _wormhole) L2WormholeRouter(_vault, _wormhole) {}

    function validateTVLMessage(bytes calldata message) external returns (bool, uint256){
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        _validateWormholeMessageEmitter(vm);
        nextValidNonce = vm.nonce + 1;
        (bytes32 msgType, uint256 tvl, bool received) = abi.decode(vm.payload, (bytes32, uint256, bool));
        require(msgType == Constants.L1_TVL, "WR: bad msg type");
        return (received, tvl);
    }

    function receiveTVL(bytes calldata message) external virtual override{
        // Silence unused variable warning
        message;
        revert("not implemented");
    }
}