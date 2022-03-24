//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";
import { IRootChainManager } from "./interfaces/IRootChainManager.sol";
import { IL1Vault, IL2Vault } from "./interfaces/IVault.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
}

contract Staging {
    using SafeTransferLib for ERC20;

    // Number of transactions sent by opposite vault to wormhole contract on opposite chain
    int32 public vaultNonce = -1;
    IWormhole public wormhole;
    address public vault;
    ERC20 public token;
    IRootChainManager public rootChainManager;
    bool public initialized;

    constructor() {}

    function initialize(
        address _vault,
        IWormhole _wormhole,
        ERC20 _token
    ) external {
        require(!initialized, "Can only init once");
        vault = _vault;
        wormhole = _wormhole;
        token = _token;
        initialized = true;
    }

    function initializeL1(IRootChainManager manager) external {
        require(msg.sender == vault, "Only vault");
        rootChainManager = manager;
    }

    // Transfer to L1
    function l2Withdraw(uint256 amount) external {
        require(msg.sender == vault, "Only vault");
        IChildERC20(address(token)).withdraw(amount);
    }

    function l2ClearFund(bytes calldata message) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);

        // TODO: check chain ID, emitter address
        // Get amount and nonce
        uint256 amount = abi.decode(vm.payload, (uint256));
        int32 nonce = int32(vm.nonce);
        require(nonce > vaultNonce, "No old transactions");
        vaultNonce = nonce;

        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Funds not received");

        IL2Vault l2Vault = IL2Vault(vault);
        token.safeTransfer(address(l2Vault), balance);

        l2Vault.afterReceive(balance);
    }

    function l1ClearFund(bytes calldata message, bytes calldata data) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);
        // TODO: check chain ID, emitter address
        // Get amount and nonce
        uint256 amount = abi.decode(vm.payload, (uint256));
        int32 nonce = int32(vm.nonce);
        require(nonce > vaultNonce, "No old transactions");
        vaultNonce = nonce;

        // Exit tokens, after that the withdrawn tokens from L2 will be reflected in L1 staging.
        rootChainManager.exit(data);

        // Transfer exited tokens to L1 Vault.
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Funds not received");

        IL1Vault l1Vault = IL1Vault(vault);
        token.safeTransfer(address(l1Vault), balance);

        l1Vault.afterReceive();
    }
}
