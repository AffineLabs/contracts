//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IWormhole} from "./interfaces/IWormhole.sol";
import {IRootChainManager} from "./interfaces/IRootChainManager.sol";
import {IL1Vault, IL2Vault} from "./interfaces/IVault.sol";
import {BaseVault} from "./BaseVault.sol";

interface IChildERC20 {
    function withdraw(uint256 amount) external;
}

contract BridgeEscrow {
    using SafeTransferLib for ERC20;

    // Number of transactions sent by opposite vault to wormhole contract on opposite chain
    int32 public vaultNonce = -1;
    address public immutable vault;
    ERC20 public immutable token;
    IRootChainManager public immutable rootChainManager;
    address public immutable wormholeRouter;

    constructor(address _vault, IRootChainManager manager) {
        vault = _vault;
        wormholeRouter = BaseVault(_vault).wormholeRouter();
        token = ERC20(BaseVault(_vault).asset());
        rootChainManager = manager;
    }

    // Transfer to L1
    function l2Withdraw(uint256 amount) external {
        require(msg.sender == vault, "BE: Only vault");
        IChildERC20(address(token)).withdraw(amount);
    }

    function l2ClearFund(uint256 amount) external {
        require(msg.sender == wormholeRouter, "BE: Only wormhole router");
        _l2Clear(amount);
    }

    function l2RescueFunds(uint256 amount) external {
        require(msg.sender == IL1Vault(vault).governance(), "BE: Only Governance");
        _l2Clear(amount);
    }

    function _l2Clear(uint256 amount) internal {
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "BE: Funds not received");
        token.safeTransfer(vault, balance);

        IL2Vault(vault).afterReceive(balance);
    }

    function l1ClearFund(uint256 amount, bytes calldata exitProof) external {
        require(msg.sender == wormholeRouter, "BE: Only wormhole router");
        _l1Clear(amount, exitProof);
    }

    /// @notice If for some reason we can't get a VAA, forcefully send the funds to the vault
    function l1RescueFunds(uint256 amount, bytes calldata exitProof) external {
        require(msg.sender == IL1Vault(vault).governance(), "BE: Only Governance");
        _l1Clear(amount, exitProof);
    }

    function _l1Clear(uint256 amount, bytes calldata exitProof) internal {
        // Exit tokens, after this the withdrawn tokens from L2 will be reflected in the L1 BridgeEscrow
        // NOTE: This function can fail if the exitProof provided is fake or has already been processed
        // In either case, we want to send at least `amount` to the vault since we know that the L2Vault sent `amount`
        try rootChainManager.exit(exitProof) {} catch {}

        // Transfer exited tokens to L1 Vault.
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "BE: Funds not received");
        token.safeTransfer(vault, balance);

        IL1Vault(vault).afterReceive();
    }
}
