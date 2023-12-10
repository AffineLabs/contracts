// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {CommonVaultTest, ERC20} from "src/test/CommonVault.t.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {L2VaultV2} from "src/vaults/cross-chain-vault/L2VaultV2.sol";
import {Vault} from "src/vaults/Vault.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";

import {console2} from "forge-std/console2.sol";

contract L2VaultV2_IntegrationTest is CommonVaultTest {
    function setUp() public virtual override {
        vm.createSelectFork("polygon", 50_951_000);

        L2Vault impl = new L2VaultV2();
        vault = VaultV2(0x829363736a5A9080e05549Db6d1271f070a7e224);

        governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        vm.prank(governance);
        vault.upgradeTo(address(impl));
        asset = ERC20(vault.asset());

        if (vault.paused()) {
            // @in case vault is paused
            vm.prank(governance);
            vault.unpause();
        }
    }

    function _giveAssets(address user, uint256 assets) internal override {
        deal(address(asset), address(user), assets);
    }
}
