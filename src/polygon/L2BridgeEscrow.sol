//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L2Vault} from "./L2Vault.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
}

contract L2BridgeEscrow is BridgeEscrow {
    using SafeTransferLib for ERC20;

    /// @notice The L2Vault.
    L2Vault public immutable vault;

    constructor(L2Vault _vault) BridgeEscrow(_vault) {
        vault = _vault;
    }

    /// @notice Send `amount` of `asset` to L1BridgeEscrow.
    function withdraw(uint256 amount) external {
        require(msg.sender == address(vault), "BE: Only vault");
        IChildERC20(address(asset)).withdraw(amount);
    }

    function _clear(uint256 amount, bytes calldata /* exitProof */ ) internal override {
        uint256 balance = asset.balanceOf(address(this));
        require(balance >= amount, "BE: Funds not received");
        asset.safeTransfer(address(vault), balance);

        emit TransferToVault(balance);
        vault.afterReceive(balance);
    }
}
