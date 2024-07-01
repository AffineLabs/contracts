// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EthVault} from "src/vaults/EthVault.sol";
import {Vault} from "src/vaults/Vault.sol";
import {Router, IWETH} from "src/vaults/cross-chain-vault/router/audited/Router.sol";

import {Base} from "./Base.sol";

/* solhint-disable reason-string, no-console */

library EthVaults {
    function deployEthWeth(address governance, address weth) internal returns (EthVault) {
        // Deploy implementation
        EthVault impl = new EthVault();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, weth, "ETH Earn Eth", "ethEarnEth"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        EthVault vault = EthVault(payable(address(proxy)));
        require(vault.governance() == governance);
        require(address(vault.asset()) == weth);
        return vault;
    }
}

contract Deploy is Script, Base {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function runEthWeth() external {
        bool testnet = vm.envBool("TEST");
        console2.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address governance = config.governance;
        address weth = config.weth;
        console2.log("weth: %s", weth);

        _start();
        EthVault vault = EthVaults.deployEthWeth(governance, weth);
        console2.log("Eth denominated vault addr:", address(vault));
        EthVault.Number memory price = vault.detailedPrice();
        console2.log("price: %s", price.num);
    }

    function routerDeploy() external {
        bool testnet = vm.envBool("TEST");
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));

        address weth = config.weth;
        console2.log("weth: %s", weth);

        _start();
        Router router = new Router("affine-router-v2", IWETH(weth));
        console2.log("router weth: %s", address(router.weth()));
    }

    function routerHoleSky() external {
        address weth = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;
        console2.log("weth: %s", weth);

        _start();
        Router router = new Router("affine-router-v2", IWETH(weth));
        console2.log("router weth: %s", address(router.weth()));
    }
}
