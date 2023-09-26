// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {Vault} from "src/vaults/Vault.sol";

/* solhint-disable reason-string, no-console */

contract BaseChainVault is VaultV2 {}

contract BaseDegenVault is VaultV2 {
    /**
     * @dev vault initial decimals fixed at 8, making initial shares to 1e6 increased the asset per share 100 times
     */
    function initialSharesPerAsset() public pure override returns (uint256) {
        return 1e6;
    }
}

contract Deploy is Script {
    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
    }

    function run() public {
        _start();
        // Deploy implementation
        BaseChainVault impl = new BaseChainVault();

        address governance = 0x535B06019dD972Cd48655F5838306dfF8E68d6FD;
        address asset = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, asset, "USD Earn Base", "usdEarnBase"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        BaseChainVault vault = BaseChainVault(address(proxy));
        require(vault.governance() == governance);
        require(address(vault.asset()) == asset);
    }

    function deployBaseDegen() public {
        _start();
        // Deploy implementation
        BaseDegenVault impl = new BaseDegenVault();

        address governance = 0x535B06019dD972Cd48655F5838306dfF8E68d6FD;
        address asset = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;

        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(Vault.initialize, (governance, asset, " Affine High Yield LP", "BaseDegen"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        BaseDegenVault vault = BaseDegenVault(address(proxy));
        require(vault.governance() == governance);
        require(address(vault.asset()) == asset);

        console2.log("detailed price %s", vault.detailedPrice().num);
        console2.log("Vault address %s", address(vault));
    }
}
