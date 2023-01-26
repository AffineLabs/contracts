// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Script.sol";

import {Base} from "./Base.sol";
import {Vault} from "../src/both/Vault.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {DeployLib} from "./ConvexStrategy.s.sol";

/* solhint-disable reason-string */

contract Deploy is Script, Base {
    function deployStrategies() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        DeployLib.deployMim3Crv(BaseVault(0x78Bb94Feab383ccEd39766a7d6CF31dED177Ad0c));
    }

    function run() external {
        // Get config info
        bool testnet = vm.envBool("TEST");
        console.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address governance = config.governance;
        address usdc = config.usdc;
        console.log("usdc: %s governance: %s", usdc, governance);

        // Start broadcasting txs
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy implementation
        Vault impl = new Vault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, usdc, "USD Earn Eth", "usdEarnEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        Vault vault = Vault(address(proxy));
        require(vault.governance() == governance);
        require(vault.asset() == usdc);
    }
}
