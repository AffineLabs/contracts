// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {AffineVault} from "src/vaults/Vault.sol";

import {BeefyStrategy} from "src/strategies/BeefyStrategy.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

contract BeefyEpochStrategy is BeefyStrategy {
    StrategyVault public immutable sVault;

    constructor(
        StrategyVault _vault,
        ICurvePool _pool,
        I3CrvMetaPoolZap _zapper,
        int128 _assetIndex,
        IBeefyVault _beefy,
        address[] memory strategists
    ) BeefyStrategy(AffineVault(address(_vault)), _pool, _zapper, _assetIndex, _beefy, strategists) {
        sVault = _vault;
    }

    function endEpoch() external onlyRole(STRATEGIST_ROLE) {
        sVault.endEpoch();
    }
}
