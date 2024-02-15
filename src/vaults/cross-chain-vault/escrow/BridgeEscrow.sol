//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/*//////////////////////////////////////////////////////////////
                            AUDIT INFO
//////////////////////////////////////////////////////////////*/
/**
 * Audits:
 *     1. Nov 8, 2022, size: 58 Line
 * Extended: No
 * Changes: None
 */
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";

abstract contract BridgeEscrow {
    using SafeTransferLib for ERC20;

    /// @notice The input asset.
    ERC20 public immutable asset;
    /// @notice The wormhole router contract.
    address public immutable wormholeRouter;
    /// @notice Governance address (shared with vault).
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

    /**
     * @notice Send assets to vault.
     * @param assets The amount of assets to send.
     * @param exitProof Proof needed by Polygon Pos bridge to unlock assets on Ethereum.
     */
    function clearFunds(uint256 assets, bytes calldata exitProof) external {
        require(msg.sender == wormholeRouter, "BE: Only wormhole router");
        _clear(assets, exitProof);
    }

    /// @notice Escape hatch for governance in an emergency.
    function rescueFunds(uint256 amount, bytes calldata exitProof) external {
        require(msg.sender == governance, "BE: Only Governance");
        _clear(amount, exitProof);
    }

    function _clear(uint256 assets, bytes calldata exitProof) internal virtual;
}
