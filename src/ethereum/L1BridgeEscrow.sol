//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IRootChainManager} from "../interfaces/IRootChainManager.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {L1Vault} from "./L1Vault.sol";

contract L1BridgeEscrow is BridgeEscrow {
    using SafeTransferLib for ERC20;

    /// @notice The L1Vault.
    L1Vault public immutable vault;
    /// @notice Polygon Pos Bridge manager. See https://github.com/maticnetwork/pos-portal/blob/41d45f7eff5b298941a2547afa0073a6c36b2b9c/contracts/root/RootChainManager/RootChainManager.sol
    IRootChainManager public immutable rootChainManager;

    constructor(L1Vault _vault, IRootChainManager _manager) BridgeEscrow(_vault) {
        vault = _vault;
        rootChainManager = _manager;
    }

    function _clear(uint256 assets, bytes calldata exitProof) internal override {
        // Exit tokens, after this the withdrawn tokens from L2 will be reflected in the L1 BridgeEscrow
        // NOTE: This function can fail if the exitProof provided is fake or has already been processed
        // In either case, we want to send at least `assets` to the vault since we know that the L2Vault sent `assets`
        try rootChainManager.exit(exitProof) {} catch {}

        // Transfer exited tokens to L1 Vault.
        uint256 balance = asset.balanceOf(address(this));
        require(balance >= assets, "BE: Funds not received");
        asset.safeTransfer(address(vault), balance);

        emit TransferToVault(balance);
        vault.afterReceive();
    }
}
