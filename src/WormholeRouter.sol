// SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import { IWormhole } from "./interfaces/IWormhole.sol";
import { BaseVault } from "./BaseVault.sol";
import { AffineGovernable } from "./AffineGovernable.sol";

abstract contract WormholeRouter is AffineGovernable {
    /** WORMHOLE CONFIGURATION
     **************************************************************************/
    address public otherLayerRouter;
    uint16 public otherLayerChainId;
    uint256 public nextVaildNonce;

    /// @notice The address of the core wormhole contract
    IWormhole public wormhole;
    /**
     * @notice This is the number of blocks it takes to emit produce the VAA.
     * See https://book.wormholenetwork.com/wormhole/4_vaa.html
     */
    uint8 public consistencyLevel = 4;

    /// @notice Set the wormhole address
    function setWormhole(IWormhole _wormhole) external onlyGovernance {
        wormhole = _wormhole;
    }

    ///@notice Set the number of blocks needed for wormhole guardians to produce VAA
    function setConsistencyLevel(uint8 _consistencyLevel) external onlyGovernance {
        consistencyLevel = _consistencyLevel;
    }

    /** VALIDATION
     **************************************************************************/
    function _validateWormholeMessageEmitter(IWormhole.VM memory vm) internal view {
        require(vm.emitterAddress == bytes32(uint256(uint160(otherLayerRouter))), "Wrong emitter address");
        require(vm.emitterChainId == otherLayerChainId, "Wrong emitter chain");
    }
}
