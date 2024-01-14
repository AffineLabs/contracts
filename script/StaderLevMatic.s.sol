// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EthVaultV2} from "src/vaults/EthVaultV2.sol";
import {Vault} from "src/vaults/VaultV2.sol";
import {Router} from "src/vaults/cross-chain-vault/router/Router.sol";

import {StaderLevMaticStrategy, IWMATIC} from "src/strategies/StaderLevMaticStrategy.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

import {Base} from "./Base.sol";

/* solhint-disable reason-string, no-console */

library polygonStader {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function deployWmaticVault(address governance, address wmatic) internal returns (EthVaultV2) {
        // Deploy implementation
        EthVaultV2 impl = new EthVaultV2();

        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(Vault.initialize, (governance, wmatic, "Stader Lev Matic", "LevMaticX"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        EthVaultV2 vault = EthVaultV2(payable(address(proxy)));
        require(vault.governance() == governance);
        require(address(vault.asset()) == wmatic);
        return vault;
    }
}

contract Deploy is Script, Base {
    address governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
    address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address wmaticVaultAddr = 0x5cfD50De188a36d2089927c5a14E143DC65Af780;

    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        console2.log("dep %s", deployer);
        vm.startBroadcast(deployer);
    }

    function runWmatic() external {
        _start();
        EthVaultV2 vault = polygonStader.deployWmaticVault(governance, wmatic);
        console2.log("Wmatic denominated vault addr:", address(vault));
        EthVaultV2.Number memory price = vault.detailedPrice();
        console2.log("price: %s", price.num);
    }

    function depStaderStrat() public {
        _start();
        AffineVault vault = AffineVault(wmaticVaultAddr);

        require(address(vault.asset()) == wmatic, "Invalid asset");

        StaderLevMaticStrategy strategy = new StaderLevMaticStrategy(vault, polygonStader._getStrategists());

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }

    function investTestMatic() public {
        _start();
        IWMATIC iWmatic = IWMATIC(payable(wmatic));
        iWmatic.deposit{value: 2 * 1e18}();

        console2.log("wmatic balance ", iWmatic.balanceOf(address(0x4E283AbD94aee0a5a64A582def7b22bba60576d8)));

        StaderLevMaticStrategy strategy = StaderLevMaticStrategy(payable(0x468798b5C389CD822cF4b2E1431f09222F606399));

        iWmatic.approve(address(strategy), 2 * 1e18);

        strategy.invest(2 * 1e18);

        console2.log("TVL %s", strategy.totalLockedValue());
    }
}
