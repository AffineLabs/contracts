// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AaveV3Strategy, IPool} from "src/strategies/AaveV3Strategy.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        AffineVault vault = AffineVault(0x3A6B57ea121fbAB06f5A7Bf0626702EcB0Db7f11);
        AaveV3Strategy strategy = new AaveV3Strategy(vault, IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5));
        require(strategy.vault() == vault);
    }

    function runPoly() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        console2.log("dep %s", deployer);

        AffineVault vault = AffineVault(0x829363736a5A9080e05549Db6d1271f070a7e224);
        AaveV3Strategy strategy = new AaveV3Strategy(vault, IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD));

        console2.log("strat %s", address(strategy));
        require(strategy.vault() == vault);
        require(address(strategy.asset()) == address(vault.asset()));
    }
}
