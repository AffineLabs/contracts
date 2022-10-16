// SPDX-License-Identifier:MIT
pragma solidity =0.8.16;

import {IWormhole} from "./interfaces/IWormhole.sol";
import {BaseVault} from "./BaseVault.sol";
import {AffineGovernable} from "./AffineGovernable.sol";
import {OwnedInitializable} from "./Initializable.sol";

contract WormholeRouter is AffineGovernable, OwnedInitializable {
    constructor(IWormhole _wormhole, uint16 _otherLayerWormholeChainId) {
        wormhole = _wormhole;
        otherLayerWormholeChainId = _otherLayerWormholeChainId;
    }
    /**
     * WORMHOLE CONFIGURATION
     *
     */

    uint16 public immutable otherLayerWormholeChainId;
    uint256 public nextValidNonce;

    /// @notice The address of the core wormhole contract
    IWormhole public immutable wormhole;
    /**
     * @notice This is the number of blocks it takes to emit produce the VAA.
     * See https://book.wormholenetwork.com/wormhole/4_vaa.html
     * @dev This consistency level is actually being ignored on Polygon as of August 16, 2022. The minium number of blocks
     * is actually hardcoded to 512. See https://github.com/certusone/wormhole/blob/9ba75ddb97162839e0cacd91851a9a0ef9b45496/node/cmd/guardiand/node.go#L969-L981
     */
    uint8 public consistencyLevel = 4;

    ///@notice Set the number of blocks needed for wormhole guardians to produce VAA
    function setConsistencyLevel(uint8 _consistencyLevel) external onlyGovernance {
        consistencyLevel = _consistencyLevel;
    }

    /**
     * VALIDATION
     *
     */
    function _validateWormholeMessageEmitter(IWormhole.VM memory vm) internal view {
        require(vm.emitterAddress == bytes32(uint256(uint160(address(this)))), "Wrong emitter address");
        require(vm.emitterChainId == otherLayerWormholeChainId, "Wrong emitter chain");
        require(vm.nonce >= nextValidNonce, "Old transaction");
    }
}
