// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {ConvexStrategy} from "src/strategies/ConvexStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "src/interfaces/convex.sol";

library DeployLib {
    function deployMim3Crv(BaseVault vault) internal returns (ConvexStrategy strategy) {
        strategy = new ConvexStrategy(
            {_vault: vault, 
            _assetIndex: 2,
            _isMetaPool: true, 
            _curvePool: ICurvePool(0x5a6A4D54456819380173272A5E8E9B9904BdF41B),
            _zapper:I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359),
            _convexPid: 40,
            strategists: _getStrategists()
            });
    }

    function _getStrategists() internal view returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runMim3Crv() external {
        _start();
        DeployLib.deployMim3Crv(BaseVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }
}
