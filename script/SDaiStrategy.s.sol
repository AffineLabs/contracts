// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/* solhint-disable reason-string, no-console */

import {Script, console2} from "forge-std/Script.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {Base} from "./Base.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {TestSDaiStrategy} from "src/strategies/deployed/TestSDaiStrategy.sol";

contract Deploy is Script, Base {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer address %s", deployer);
    }

    function run() external {
        _start();

        AffineVault vault = AffineVault(0x61A18EE9d6d51F838c7e50dFD750629Fd141E944); // tmpUSDC vault

        require(address(vault.asset()) == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "Invalid asset");

        address[] memory strategists = new address[](1);
        strategists[0] = 0x4E283AbD94aee0a5a64A582def7b22bba60576d8; // deployer is strategist to withdraw

        TestSDaiStrategy strategy = new TestSDaiStrategy(vault, strategists);

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }
}
