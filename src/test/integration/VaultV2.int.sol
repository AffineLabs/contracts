// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {CommonVaultTest, ERC20} from "src/test/CommonVault.t.sol";
import {Vault} from "src/vaults/Vault.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";

import "forge-std/console2.sol";

abstract contract VaultV2_IntegrationTest is CommonVaultTest {
    function _fork() internal virtual {}

    function _vault() internal virtual returns (address) {}

    function setUp() public virtual override {
        _fork();

        VaultV2 impl = new VaultV2();
        vault = VaultV2(_vault());

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

contract SthEthLevPolygon_IntegrationTest is VaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("polygon", 45_620_526);
    }

    function _vault() internal override returns (address) {
        return 0xa92B1D196F0Df5F17215698f5de99eED26B659bF;
    }
}

contract StEthLev_IntegrationTest is VaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("ethereum", 17_791_940);
    }

    function _vault() internal override returns (address) {
        return 0x1196B60c9ceFBF02C9a3960883213f47257BecdB;
    }
}
