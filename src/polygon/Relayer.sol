// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";
import { L2Vault } from "./L2Vault.sol";

contract Relayer is BaseRelayRecipient {
    L2Vault vault;
    address owner;
    bool initialized;

    constructor() {
        owner = msg.sender;
    }

    function initialize(address _forwarder, L2Vault _vault) external {
        require(!initialized, "INIT_CALLED_BEFORE");
        require(msg.sender == owner, "ONLY_OWNER");
        _setTrustedForwarder(_forwarder);
        vault = _vault;
        initialized = true;
    }

    function deposit(uint256 amountToken) external {
        vault.depositGasLess(_msgSender(), amountToken);
    }

    function redeem(uint256 shares) external {
        vault.redeemGasLess(_msgSender(), shares);
    }

    function withdraw(uint256 amountToken) external {
        vault.withdrawGasLess(_msgSender(), amountToken);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }
}
