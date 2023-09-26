// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ICurvePool, I3CrvMetaPoolZap} from "src/interfaces/curve.sol";
import {IBeefyVault} from "src/interfaces/Beefy.sol";
import {IRouter, IPair} from "src/interfaces/IPearl.sol";
import {IAeroRouter} from "src/interfaces/aerodrome.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {BeefyEpochStrategy} from "src/strategies/BeefyEpochStrategy.sol";
import {BeefyPearlEpochStrategy} from "src/strategies/BeefyPearlStrategy.sol";
import {BeefyAeroStrategy} from "src/strategies/BeefyAeroStrategy.sol";
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

    function deployBeefyPearlStrategy() internal returns (BeefyPearlEpochStrategy strategy) {
        IRouter router = IRouter(0xcC25C0FD84737F44a7d38649b69491BBf0c7f083);
        IBeefyVault beefy = IBeefyVault(0xD74B5df80347cE9c81b91864DF6a50FfAfE44aa5);
        ERC20 token1 = ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa); // usdr
        StrategyVault vault = StrategyVault(0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46);

        strategy = new BeefyPearlEpochStrategy(
            vault, 
            beefy,
            router,
            token1,
            _getStrategists()
        );
    }

    function deployBeefyAeroStrategy() internal returns (BeefyAeroStrategy strategy) {
        IAeroRouter router = IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
        IBeefyVault beefy = IBeefyVault(0x8aeDd79BC918722d4948502b18deceaBeD60d044);
        ERC20 token1 = ERC20(0x9483ab65847A447e36d21af1CaB8C87e9712ff93); // wusdr
        VaultV2 vault = VaultV2(0xcb3f73F228B8980ec0766735b8F5551935556354);
        strategy = new BeefyAeroStrategy(
            vault, 
            beefy,
            router,
            token1,
            _getStrategists()
        );
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer %s", deployer);
    }

    function deployBeefyEpochStrategyPolygon() public {
        _start();
        BeefyEpochStrategy strategy = BeefyLib.deployBeefyStrategy();
        console2.log("Beefy strategy addr: %s", address(strategy));
    }

    function deployBeefyPearlEpochStrategyPolygon() public {
        _start();
        BeefyPearlEpochStrategy strategy = BeefyLib.deployBeefyPearlStrategy();
        console2.log("Beefy Pearl Strategy addr: %s", address(strategy));
    }

    function deployBeefyAeroStrategyBase() public {
        _start();
        BeefyAeroStrategy strategy = BeefyLib.deployBeefyAeroStrategy();
        console2.log("Beefy Aero Strategy Addr: %s", address(strategy));
    }
}
