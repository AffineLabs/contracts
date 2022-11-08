//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {BaseVault} from "./BaseVault.sol";

abstract contract BridgeEscrow {
    using SafeTransferLib for ERC20;

    ERC20 public immutable asset;
    address public immutable wormholeRouter;
    address public immutable governance;

    /**
     * @notice Emitted whenever we transfer funds from this escrow to the vault
     * @param assets The amount of assets transferred
     */
    event TransferToVault(uint256 assets);

    constructor(BaseVault _vault) {
        wormholeRouter = _vault.wormholeRouter();
        asset = ERC20(_vault.asset());
        governance = _vault.governance();
    }

    function clearFunds(uint256 assets, bytes calldata exitProof) external {
        require(msg.sender == wormholeRouter, "BE: Only wormhole router");
        _clear(assets, exitProof);
    }

    function rescueFunds(uint256 amount, bytes calldata exitProof) external {
        require(msg.sender == governance, "BE: Only Governance");
        _clear(amount, exitProof);
    }

    function _clear(uint256 assets, bytes calldata exitProof) internal virtual;
}
