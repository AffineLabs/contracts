// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

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
}
