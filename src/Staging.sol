//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { IWormhole } from "./interfaces/IWormhole.sol";
import { IRootChainManager } from "./interfaces/IRootChainManager.sol";
import { L1Vault } from "./ethereum/L1Vault.sol";
import { L2Vault } from "./polygon/L2Vault.sol";
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

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function initialize(
        address _vault,
        IWormhole _wormhole,
        ERC20 _token,
        IRootChainManager manager
    ) external {
        require(msg.sender == owner, "ONLY_OWNER");
        require(!initialized, "INIT_DONE");
        vault = _vault;
        wormhole = _wormhole;
        token = _token;
        rootChainManager = manager;
        initialized = true;
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

        L2Vault l2Vault = L2Vault(vault);
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

        L1Vault l1Vault = L1Vault(vault);
        token.safeTransfer(address(l1Vault), balance);

        l1Vault.afterReceive();
    }
}
