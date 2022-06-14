// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { BridgeEscrow } from "../BridgeEscrow.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { BaseVault } from "../BaseVault.sol";

contract TestStrategy is BaseStrategy {
    constructor(MockERC20 _token, BaseVault _vault) {
        token = _token;
        vault = _vault;
    }

    function balanceOfToken() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function invest(uint256 amount) public override {}

    function divest(uint256 amount) public override returns (uint256) {
        token.transfer(address(vault), amount);
        return amount;
    }

    function totalLockedValue() public override returns (uint256) {
        return balanceOfToken();
    }
}

contract BaseVaultLiquidate is BaseVault {
    function liquidate(uint256 amount) public returns (uint256) {
        return _liquidate(amount);
    }
}

contract VaultTest is TestPlus {
    MockERC20 token;
    BaseVaultLiquidate vault;
    uint8 constant MAX_STRATEGIES = 20;

    function setUp() public {
        token = new MockERC20("Mock", "MT", 18);
        vault = new BaseVaultLiquidate();
        vault.init(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            BridgeEscrow(address(0))
        );
    }

    function testHarvest() public {
        BaseStrategy newStrategy1 = new TestStrategy(token, vault);
        vault.addStrategy(newStrategy1, 1000);
        token.mint(address(newStrategy1), 1000);
        assertTrue(newStrategy1.balanceOfToken() != 0);
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = newStrategy1;
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);
        vault.harvest(strategies);
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);
        assert(vault.vaultTVL() == 1000);
    }

    function testStrategyAddition() public {
        TestStrategy strategy = new TestStrategy(token, vault);
        vault.addStrategy(strategy, 1000);
        assertEq(address(vault.withdrawalQueue(0)), address(strategy));
        (, uint256 tvlBps, , , ) = vault.strategies(strategy);
        assertEq(tvlBps, 1000);
    }

    function testStrategyRemoval() public {
        TestStrategy strategy = new TestStrategy(token, vault);
        vault.removeStrategy(strategy);
        (bool isActive, uint256 tvlBps, , , ) = vault.strategies(strategy);
        assertEq(tvlBps, 0);
        assertTrue(isActive == false);
        assertEq(address(vault.withdrawalQueue(0)), address(0));
    }

    function testGetWithdrawalQueue() public {
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            vault.addStrategy(new TestStrategy(token, vault), 10);
        }
        for (uint256 i = 0; i < vault.MAX_STRATEGIES(); i++) {
            assertTrue(vault.getWithdrawalQueue()[i] == vault.withdrawalQueue(i));
        }
    }

    event WithdrawalQueueSet(address indexed user, BaseStrategy[MAX_STRATEGIES] replacedWithdrawalQueue);

    event WithdrawalQueueIndexesSwapped(
        address indexed user,
        uint256 index1,
        uint256 index2,
        BaseStrategy indexed newStrategy1,
        BaseStrategy indexed newStrategy2
    );

    function testSetWithdrawalQueue() public {
        BaseStrategy[MAX_STRATEGIES] memory newQueue;
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            newQueue[i] = new TestStrategy(token, vault);
        }
        vault.setWithdrawalQueue(newQueue);
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            assertTrue(vault.withdrawalQueue(i) == newQueue[i]);
        }
    }

    function testSwapWithdrawalQueue() public {
        vault.addStrategy(new TestStrategy(token, vault), 1000);
        vault.addStrategy(new TestStrategy(token, vault), 2000);
        BaseStrategy newStrategy1 = vault.withdrawalQueue(0);
        BaseStrategy newStrategy2 = vault.withdrawalQueue(1);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalQueueIndexesSwapped(address(this), 0, 1, newStrategy2, newStrategy1);
        vault.swapWithdrawalQueueIndexes(0, 1);
        assertTrue(newStrategy1 == vault.withdrawalQueue(1));
        assertTrue(newStrategy2 == vault.withdrawalQueue(0));
    }

    function testLiquidate() public {
        BaseStrategy newStrategy1 = new TestStrategy(token, vault);
        token.mint(address(newStrategy1), 10);
        vault.addStrategy(newStrategy1, 10);
        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = newStrategy1;
        vm.warp(vault.lastHarvest() + vault.lockInterval() + 1);
        vault.harvest(strategies);
        vault.liquidate(10);
        assertTrue(token.balanceOf(address(vault)) == 10);
        assertTrue(newStrategy1.balanceOfToken() == 0);
    }
}
