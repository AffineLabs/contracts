// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {StakingExp, IBalancerVault} from "src/strategies/Staking.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        // vm.startBroadcast(deployer);

        // address owner = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        // StakingExp staking = new StakingExp(IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8), owner);

        // require(staking.owner() == owner);
    }
}
