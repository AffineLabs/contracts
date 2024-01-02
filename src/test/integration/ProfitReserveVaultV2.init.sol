// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {CommonVaultTest, ERC20, TestPlus} from "src/test/CommonVault.t.sol";
import {Vault} from "src/vaults/Vault.sol";
import {ProfitReserveVaultV2} from "src/vaults/ProfitReserveVaultV2.sol";

import "forge-std/console2.sol";

abstract contract ProfitReserveVaultV2_IntegrationTest is CommonVaultTest {
    function _fork() internal virtual {}

    function _vault() internal virtual returns (address) {}

    function setUp() public virtual override {
        _fork();

        ProfitReserveVaultV2 impl = new ProfitReserveVaultV2();
        vault = ProfitReserveVaultV2(_vault());

        governance = vault.governance();
        vm.prank(governance);
        vault.upgradeTo(address(impl));
        asset = ERC20(vault.asset());
    }

    function _giveAssets(address user, uint256 assets) internal override {
        uint256 currBal = asset.balanceOf(user);
        deal(address(asset), address(user), currBal + assets);
    }
}

contract ProfResSthEthLevPolygon_IntegrationTest is ProfitReserveVaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("polygon", 51_860_000);
    }

    function _vault() internal override returns (address) {
        return 0xa92B1D196F0Df5F17215698f5de99eED26B659bF;
    }
}

contract ProfResStEthLev_IntegrationTest is ProfitReserveVaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("ethereum", 18_922_000);
    }

    function _vault() internal override returns (address) {
        return 0x1196B60c9ceFBF02C9a3960883213f47257BecdB;
    }
}

abstract contract ReserveProfit_UpgradeIntegrationStorageTest is TestPlus {
    ProfitReserveVaultV2 vault;
    ERC20 asset;

    function _fork() internal virtual {}

    function _vault() internal virtual returns (address) {}

    function setUp() public {
        _fork();
        vault = ProfitReserveVaultV2(_vault());
        asset = ERC20(vault.asset());
        governance = vault.governance();
    }

    function _upgrade() internal {
        ProfitReserveVaultV2 impl = new ProfitReserveVaultV2();
        vm.prank(governance);
        vault.upgradeTo(address(impl));
    }

    function testStorageValueCheck() public {
        // check storage value from reading public functions
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        bytes32 harvesterRole = vault.HARVESTER();
        uint256 lockInterval = vault.LOCK_INTERVAL();
        address vaultAsset = vault.asset();
        uint128 lastHarvest = vault.lastHarvest();
        string memory name = vault.name();
        string memory symbol = vault.symbol();
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        address accessNft = address(vault.accessNft());
        uint256 accumulatedPerformanceFee = vault.accumulatedPerformanceFee();
        address _gov = vault.governance();

        _upgrade();

        assertTrue(adminRole == vault.DEFAULT_ADMIN_ROLE());
        assertTrue(harvesterRole == vault.HARVESTER());
        assertTrue(lockInterval == vault.LOCK_INTERVAL());
        assertTrue(vaultAsset == vault.asset());
        assertTrue(lastHarvest == vault.lastHarvest());
        assertEq(name, vault.name());
        assertEq(symbol, vault.symbol());
        assertTrue(totalAssets == vault.totalAssets());
        assertTrue(totalSupply == vault.totalSupply());

        assertEq(accessNft, address(vault.accessNft()));
        assertTrue(accumulatedPerformanceFee == vault.accumulatedPerformanceFee());
        assertEq(_gov, vault.governance());
    }
}

contract ProfResSthEthLevPolygonStorage_IntegrationTest is ReserveProfit_UpgradeIntegrationStorageTest {
    function _fork() internal override {
        vm.createSelectFork("polygon", 51_860_000);
    }

    function _vault() internal override returns (address) {
        return 0xa92B1D196F0Df5F17215698f5de99eED26B659bF;
    }
}

contract ProfResStEthLevStorage_IntegrationTest is ReserveProfit_UpgradeIntegrationStorageTest {
    function _fork() internal override {
        vm.createSelectFork("ethereum", 18_922_000);
    }

    function _vault() internal override returns (address) {
        return 0x1196B60c9ceFBF02C9a3960883213f47257BecdB;
    }
}
