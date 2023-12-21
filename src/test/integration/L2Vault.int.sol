// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {L2Vault, TestPlus} from "src/test/L2Vault.t.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract L2Vault_UpgradeIntegrationStorageTest is TestPlus {
    L2Vault vault;
    ERC20 asset;

    function setUp() public {
        vm.createSelectFork("polygon", 50_951_000);
        governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        vault = L2Vault(0x829363736a5A9080e05549Db6d1271f070a7e224);
        asset = ERC20(vault.asset());
    }

    function _upgrade() internal {
        L2Vault impl = new L2Vault();
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
