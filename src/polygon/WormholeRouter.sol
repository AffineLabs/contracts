// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;


import { IWormhole } from "../interfaces/IWormhole.sol";
import { Staging } from "../Staging.sol";
import { L2Vault } from "./L2Vault.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Constants } from "../Constants.sol";

contract WormholeRouter is AccessControl {
    IWormhole public wormhole;
    L2Vault public vault;
    Staging public staging;

    bool initialized = false;

    uint256 nextVaildNonce;

    constructor() {}

    function initialize(
        IWormhole _wormhole,
        L2Vault _vault,
        Staging _staging
    ) external {
        wormhole = _wormhole;
        vault = _vault;
        staging = _staging;
    }

    function receiveFund(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);

        // TODO: check chain ID, emitter address
        // Get amount and nonce
        (bytes32 msgType, uint256 amount) = abi.decode(vm.payload, (bytes32, uint256));
        nextVaildNonce = vm.nonce + 1;

        staging.l2ClearFund(msgType, amount);
    }

    function receiveTVL(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        require(vm.nonce >= nextVaildNonce, "Old TVL");
        nextVaildNonce = vm.nonce + 1;

        // TODO: check chain ID, emitter address
        // Get tvl from payload
        (uint256 tvl, bool received) = abi.decode(vm.payload, (uint256, bool));
        
        vault.receiveTVL(tvl, received);
    }
}