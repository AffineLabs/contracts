//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";
import { IRootChainManager } from "./interfaces/IRootChainManager.sol";
import { IL1Vault, IL2Vault } from "./interfaces/IVault.sol";
import { Initializable } from "./Initializable.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
}

contract Staging is Initializable {
    using SafeTransferLib for ERC20;

    // Number of transactions sent by opposite vault to wormhole contract on opposite chain
    int32 public vaultNonce = -1;
    IWormhole public wormhole;
    address public vault;
    ERC20 public token;
    IRootChainManager public rootChainManager;
    address public wormholeRouter;
    bool public initialized;

    constructor() {}

    function initialize(
        address _vault,
        address _wormhole,
        address _token,
        address _wormholeRouter
    ) external initializer() {
        vault = _vault;
        wormhole = IWormhole(_wormhole);
        token = ERC20(_token);
        wormholeRouter = _wormholeRouter;
    }

    function initializeL1(address manager) external onlyIfInitialized() {
        require(msg.sender == vault, "Only vault");
        rootChainManager = IRootChainManager(manager);
    }

    // Transfer to L1
    function l2Withdraw(uint256 amount) external onlyIfInitialized() {
        require(msg.sender == vault, "Only vault");
        IChildERC20(address(token)).withdraw(amount);
    }

    function l2ClearFund(uint256 amount) external onlyIfInitialized() {
        require(msg.sender == wormholeRouter, "Only L2 wormhole router");
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Funds not received");

        IL2Vault l2Vault = IL2Vault(vault);
        token.safeTransfer(address(l2Vault), balance);

        l2Vault.afterReceive(balance);
    }

    function l1ClearFund(uint256 amount, bytes calldata data) external onlyIfInitialized() {
        require(msg.sender == wormholeRouter, "Only L1 wormhole router");
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
