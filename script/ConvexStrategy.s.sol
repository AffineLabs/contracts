// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {ConvexStrategy} from "src/strategies/ConvexStrategy.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "src/interfaces/convex.sol";

/* solhint-disable reason-string, no-console */

library DeployLib {
    function deployMim3Crv(AffineVault vault) internal returns (ConvexStrategy strategy) {
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

    function _getStrategists() internal pure returns (address[] memory strategists) {
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
        DeployLib.deployMim3Crv(AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9));
    }

    function usdEarnEth() external {
        _start();
        ConvexStrategy strat = DeployLib.deployMim3Crv(AffineVault(0x78Bb94Feab383ccEd39766a7d6CF31dED177Ad0c));
        console2.log("vault: ", address(strat.vault()));
    }
}
