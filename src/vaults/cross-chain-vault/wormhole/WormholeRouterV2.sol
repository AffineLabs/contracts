// SPDX-License-Identifier:MIT
pragma solidity =0.8.16;

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {BaseVaultV2} from "src/vaults/cross-chain-vault/BaseVaultV2.sol";
import {AffineGovernable} from "src/utils/AffineGovernable.sol";

abstract contract WormholeRouterV2 is AffineGovernable {
    /// @notice The vault that sends/receives messages.
    BaseVaultV2 public vault;

    constructor(BaseVaultV2 _vault, IWormhole _wormhole) {
        vault = _vault;
        governance = vault.governance();
        wormhole = _wormhole;
    }

    /*//////////////////////////////////////////////////////////////
                         WORMHOLE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the core wormhole contract.
    IWormhole public immutable wormhole;
    /**
     * @notice The number of blocks it takes to emit produce the VAA.
     * See https://book.wormholenetwork.com/wormhole/4_vaa.html
     * @dev This consistency level is actually being ignored on Polygon as of August 16, 2022. The minimum number of blocks
     * is actually hardcoded to 512. See https://github.com/certusone/wormhole/blob/9ba75ddb97162839e0cacd91851a9a0ef9b45496/node/cmd/guardiand/node.go#L969-L981
     */
    uint8 public consistencyLevel = 4;

    ///@notice Set the number of blocks needed for wormhole guardians to produce VAA
    function setConsistencyLevel(uint8 _consistencyLevel) external onlyGovernance {
        consistencyLevel = _consistencyLevel;
    }

    /*//////////////////////////////////////////////////////////////
                             WORMHOLE STATE
    //////////////////////////////////////////////////////////////*/

    function otherLayerWormholeId() public view virtual returns (uint16) {}

    address public otherLayerEmitter;

    uint256 public nextValidNonce;

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateWormholeMessageEmitter(IWormhole.VM memory vm) internal view {
        require(vm.emitterAddress == bytes32(uint256(uint160(otherLayerEmitter))), "WR: bad emitter address");
        require(vm.emitterChainId == otherLayerWormholeId(), "WR: bad emitter chain");
        require(vm.nonce >= nextValidNonce, "WR: old transaction");
    }
}
