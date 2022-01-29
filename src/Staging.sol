//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { IWormhole } from "./interfaces/IWormhole.sol";
import { IRootChainManager } from "./interfaces/IRootChainManager.sol";
import { IL1Vault, IL2Vault } from "./interfaces/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address who) external view returns (uint256);
}

contract Staging {
    // Number of transactions sent by opposite vault to wormhole contract on opposite chain
    int32 public vaultNonce = -1;
    IWormhole public wormhole;
    address public vault;
    IChildERC20 public token;
    IRootChainManager public rootChainManager;
    bool initialized;

    constructor() {}

    function initialize(
        address _vault,
        address _wormhole,
        address _token
    ) external {
        require(!initialized, "Can only init once");
        vault = _vault;
        wormhole = IWormhole(_wormhole);
        token = IChildERC20(_token);
        initialized = true;
    }

    function initializeL1(address manager) external {
        require(msg.sender == vault, "Only vault");
        rootChainManager = IRootChainManager(manager);
    }

    // Transfer to L1
    function l2Withdraw(uint256 amount) external {
        require(msg.sender == vault);
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
        token.transfer(address(l2Vault), balance);

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
        token.transfer(address(l1Vault), balance);

        l1Vault.afterReceive();
    }
}
