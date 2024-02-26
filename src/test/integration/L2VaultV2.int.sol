// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {CommonVaultTest, ERC20, TestPlus} from "src/test/CommonVault.t.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/audited/L2Vault.sol";
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

contract L2VaultV2_UpgradeIntegrationStorageTest is TestPlus {
    L2VaultV2 vault;
    ERC20 asset;

    function setUp() public {
        vm.createSelectFork("polygon", 50_951_000);
        governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        vault = L2VaultV2(0x829363736a5A9080e05549Db6d1271f070a7e224);
        asset = ERC20(vault.asset());
    }

    function _upgrade() internal {
        L2Vault impl = new L2VaultV2();
        vm.prank(governance);
        vault.upgradeTo(address(impl));
    }

    function testStorageValueCheck() public {
        // check storage value from reading public functions
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        bytes32 harvesterRole = vault.HARVESTER();
        uint256 lockInterval = vault.LOCK_INTERVAL();
        address vaultAsset = vault.asset();
        address ewq = address(vault.emergencyWithdrawalQueue());
        uint8 l1Ratio = vault.l1Ratio();
        uint256 l1TotalLockedValue = vault.l1TotalLockedValue();
        uint128 lastHarvest = vault.lastHarvest();
        string memory name = vault.name();
        uint224 rebalanceDelta = vault.rebalanceDelta();
        string memory symbol = vault.symbol();
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        address wormholeRouter = vault.wormholeRouter();

        _upgrade();

        assertTrue(adminRole == vault.DEFAULT_ADMIN_ROLE());
        assertTrue(harvesterRole == vault.HARVESTER());
        assertTrue(lockInterval == vault.LOCK_INTERVAL());
        assertTrue(vaultAsset == vault.asset());
        assertTrue(ewq == address(vault.emergencyWithdrawalQueue()));
        assertTrue(l1Ratio == vault.l1Ratio());
        assertTrue(l1TotalLockedValue == vault.l1TotalLockedValue());
        assertTrue(lastHarvest == vault.lastHarvest());
        assertEq(name, vault.name());
        assertTrue(rebalanceDelta == vault.rebalanceDelta());
        assertEq(symbol, vault.symbol());
        assertTrue(totalAssets == vault.totalAssets());
        assertTrue(totalSupply == vault.totalSupply());
        assertTrue(wormholeRouter == vault.wormholeRouter());
    }
}
