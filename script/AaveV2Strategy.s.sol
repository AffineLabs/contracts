// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AaveV2Strategy, ILendingPool} from "src/strategies/AaveV2Strategy.sol";

/* solhint-disable reason-string */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        AffineVault vault = AffineVault(0x84eF1F1A7f14A237c4b1DA8d13548123879FC3A9);
        AaveV2Strategy strategy = new AaveV2Strategy(vault, ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9));
        require(strategy.vault() == vault);
    }
}
