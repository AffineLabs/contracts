// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus, console} from "src/test/TestPlus.sol";

import {SSVDeltaNeutralLp} from "src/strategies/SSVDeltaNeutralLp.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";

import {SSV} from "script/TestStrategyVault.s.sol";

contract SSVDeltaNeutralLp__IntegrationTest is TestPlus {
    SSVDeltaNeutralLp strategy;
    StrategyVault vault;
    WithdrawalEscrow escrow;

    uint256 startBlock = 17_168_737;

    ERC20 asset;

    function setUp() public {
        vm.createSelectFork("ethereum", startBlock);
        strategy = SSVDeltaNeutralLp(0x4306c088Fa31fE77dA9F513Ea31823E877417243);
        vault = StrategyVault(address(strategy.vault()));
        asset = ERC20(vault.asset());
    }

    function testBalances() public {
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(startBlock - 1);
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(17_146_481);
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(17_145_511);
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(17_141_159);
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(17_141_158);
        console.log("asset", asset.balanceOf(address(vault)));

        vm.rollFork(15_537_393);
        console.log("asset", asset.balanceOf(address(vault)));
    }
}
