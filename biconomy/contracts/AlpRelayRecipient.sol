// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

import {BaseRelayRecipient} from "@opengsn/contracts/src/BaseRelayRecipient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Vault} from "./Vault.sol";

contract AlpRelayRecipient is Ownable, BaseRelayRecipient {
    address public vaultAddr;

    constructor(address _trustedForwarder, address _vault) {
        vaultAddr = _vault;
        _setTrustedForwarder(_trustedForwarder);
    }

    function deposit(uint256 amountUsdc) public {
        Vault(vaultAddr).deposit(_msgSender(), amountUsdc);
    }

    function withdraw(uint256 amountAlpUsdc) public {
        Vault(vaultAddr).withdraw(_msgSender(), amountAlpUsdc);
    }

    function setVault(address _vault) external onlyOwner {
        vaultAddr = _vault;
    }

    function setTrustedForwarder(address _forwarder) external onlyOwner {
        _setTrustedForwarder(_forwarder);
    }

    function _msgSender()
        internal
        view
        override(Context, BaseRelayRecipient)
        returns (address sender)
    {
        sender = BaseRelayRecipient._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, BaseRelayRecipient)
        returns (bytes calldata)
    {
        return BaseRelayRecipient._msgData();
    }

    /**
     * Override this function.
     * This version is to keep track of BaseRelayRecipient you are using
     * in your contract.
     */
    function versionRecipient() external view override returns (string memory) {
        return "1";
    }
}
