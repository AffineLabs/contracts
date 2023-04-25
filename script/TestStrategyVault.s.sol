// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize, (deployer, 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3, "Test Sushi SSV", "tSSV")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), deployer));
        require(sVault.asset() == 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3);

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = deployer;
        MockEpochStrategy strategy = new MockEpochStrategy(sVault, strategists);

        // Add strategy to vault
        sVault.setStrategy(strategy);
        require(sVault.strategy() == strategy);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);
        sVault.setEscrow(escrow);
        require(sVault.debtEscrow() == escrow);
    }

    function deployStrategy() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = deployer;
        MockEpochStrategy strategy = new MockEpochStrategy(sVault, strategists);

        // Add strategy to vault
        sVault.setStrategy(strategy);
        require(sVault.strategy() == strategy);
    }

    function mint() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console.log("strategy: %s", address(strategy));

        strategy.mint(100);
    }

    function lock() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console.log("Current epoch: ", sVault.epoch());
        console.log("Epoch ended: %s", sVault.epochEnded());
        strategy.beginEpoch();
    }

    function unlock() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console.log("Current epoch: ", sVault.epoch());
        console.log("Epoch ended: %s", sVault.epochEnded());
        strategy.endEpoch();
    }
}
