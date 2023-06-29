// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";
import {Base} from "./Base.sol";

/* solhint-disable reason-string, no-console */

library BeefyLib {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function deployBeefyStrategy() internal returns (BeefyEpochStrategy strategy) {
        ICurvePool pool = ICurvePool(0xa138341185a9D0429B0021A11FB717B225e13e1F);
        I3CrvMetaPoolZap zapper = I3CrvMetaPoolZap(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);
        IBeefyVault beefy = IBeefyVault(0x2520D50bfD793D3C757900D81229422F70171969);
        StrategyVault vault = StrategyVault(0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46);

        strategy = new BeefyEpochStrategy(
            vault, 
            pool,
            zapper,
            2,
            beefy,
            _getStrategists()
        );
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console.log("deployer %s", deployer);
    }

    function deployBeefyEpochStrategyPolygon() public {
        _start();
        BeefyEpochStrategy strategy = BeefyLib.deployBeefyStrategy();
        console.log("Beefy strategy addr: %s", address(strategy));
    }
}
