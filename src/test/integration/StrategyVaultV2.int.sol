// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {CommonVaultTest, ERC20} from "src/test/CommonVault.t.sol";
import {StrategyVaultV2} from "src/vaults/locked/StrategyVaultV2.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {TestStrategy, BaseStrategy} from "../mocks/TestStrategy.sol";
import "forge-std/console.sol";

abstract contract StrategyVaultV2_IntegrationTest is CommonVaultTest {
    function _fork() internal virtual {}

    function _vault() internal virtual returns (address) {}

    function setUp() public virtual override {
        _fork();

        StrategyVaultV2 impl = new StrategyVaultV2();
        // `vault` has type `VaultV2` in the base test.
        // This is fine since the functions we call are shared with `VaultV2`.
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

    function _getStrategy() internal override returns (BaseStrategy) {
        StrategyVaultV2 _vault = StrategyVaultV2(address(vault));
        BaseStrategy currStrat = _vault.strategy();
        if (address(currStrat) != address(0)) return currStrat;

        TestStrategy strategy = new TestStrategy(vault);
        vm.prank(governance);
        _vault.setStrategy(strategy);
        return strategy;
    }

    function _harvest(BaseStrategy strat) internal override {
        StrategyVaultV2 _vault = StrategyVaultV2(address(vault));
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        vm.prank(address(strat));
        _vault.endEpoch();

        // unlock profit
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
    }
}

contract PolygonDegen_IntegrationTest is StrategyVaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("polygon", 45_620_526);
    }

    function _vault() internal override returns (address) {
        return 0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46;
    }
}

// The strategy must be liquid at this block
contract EthDegen_IntegrationTest is StrategyVaultV2_IntegrationTest {
    function _fork() internal override {
        vm.createSelectFork("ethereum", 17_791_940);
    }

    function _vault() internal override returns (address) {
        return 0x9d39ba71f30f44FB72e7b45151C27079C2cd8ECa;
    }
}

contract EthSushiLp_IntegrationTest is StrategyVaultV2_IntegrationTest {
    // We ended a position the block before
    function _fork() internal override {
        vm.createSelectFork("ethereum", 17_801_758);
    }

    function _vault() internal override returns (address) {
        return 0x61A18EE9d6d51F838c7e50dFD750629Fd141E944;
    }
}
