// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {L2VaultV2} from "src/vaults/cross-chain-vault/L2VaultV2.sol";
import {RebalanceModule} from "src/vaults/cross-chain-vault/RebalanceModule.sol";

import {L2VaultTest, AffineVault, Deploy, MockL2Vault} from "./L2Vault.t.sol";

import {BaseStrategy, TestStrategy} from "./mocks/TestStrategy.sol";

contract L2VaultV2Test is L2VaultTest {
    function _deployVault() internal override {
        vault = MockL2Vault(address(Deploy.deployL2VaultV2()));
    }

    /// @notice Test internal rebalancing of vault.
    function testRebalance() public {
        BaseStrategy strat1 = new TestStrategy(AffineVault(address(vault)));
        BaseStrategy strat2 = new TestStrategy(AffineVault(address(vault)));

        vm.startPrank(governance);
        vault.addStrategy(strat1, 6000);
        vault.addStrategy(strat2, 4000);
        vm.stopPrank();

        // strat1 should have 6000 and strat2 should have 4000. Since we switch the numbers, calling `rebalance`
        // will move 2000 of `asset` from strat2 to strat1
        asset.mint(address(strat1), 4000);
        asset.mint(address(strat2), 6000);

        // Harvest
        BaseStrategy[] memory strategies = new BaseStrategy[](2);
        strategies[0] = strat1;
        strategies[1] = strat2;
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
        vm.prank(governance); // gov has all roles
        vault.harvest(strategies);

        vm.startPrank(governance);
        RebalanceModule module = new RebalanceModule();
        L2VaultV2(address(vault)).setRebalanceModule(address(module));
        vault.grantRole(vault.HARVESTER(), address(module));
        vault.rebalance();
        vm.stopPrank();

        assertTrue(asset.balanceOf(address(strat1)) == 6000);
        assertTrue(asset.balanceOf(address(strat2)) == 4000);
    }
}
