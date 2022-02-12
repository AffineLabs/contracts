// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;
import { L2Vault } from "./L2Vault.sol";
import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";

contract Relayer is BaseRelayRecipient {
    L2Vault vault;

    constructor(address _forwarder, address _vault) {
        _setTrustedForwarder(_forwarder);
        vault = L2Vault(_vault);
    }

    function deposit(uint256 amountToken) external {
        vault.depositGasLess(_msgSender(), amountToken);
    }

    function withdraw(uint256 shares) external {
        vault.withdrawGasLess(_msgSender(), shares);
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }
}
