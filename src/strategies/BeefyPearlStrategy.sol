// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {AccessStrategy} from "src/strategies/AccessStrategy.sol";

import {AffineVault} from "src/vaults/Vault.sol";

contract BeefyPearlStrategy is AccessStrategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // beefy vault
    IBeefyVault public immutable beefy;
    // const max bps
    uint256 public constant MAX_BPS = 10_000;
    uint256 public defaultSlippageBps;

    constructor(AffineVault _vault, IBeefyVault _beefy, address[] memory strategists)
        AccessStrategy(_vault, strategists)
    {
        beefy = _beefy;
    }
}
