// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";
import { L2Vault } from "./L2Vault.sol";
import { Initializable } from "../Initializable.sol";

contract Relayer is BaseRelayRecipient, Initializable {
    L2Vault vault;
    address owner;

    constructor() {
        owner = msg.sender;
    }

    function initialize(address _forwarder, L2Vault _vault) external initializer() {
        require(msg.sender == owner, "ONLY_OWNER");
        _setTrustedForwarder(_forwarder);
        vault = _vault;
    }

    function deposit(uint256 amountToken) external onlyIfInitialized() {
        vault.depositGasLess(_msgSender(), amountToken);
    }

    function redeem(uint256 shares) external onlyIfInitialized() {
        vault.redeemGasLess(_msgSender(), shares);
    }

    function withdraw(uint256 amountToken) external onlyIfInitialized() {
        vault.withdrawGasLess(_msgSender(), amountToken);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }
}
