// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { BaseVault } from "../BaseVault.sol";

contract TestStrategy is BaseStrategy {
    constructor(MockERC20 _token, BaseVault _vault) {
        token = _token;
        vault = _vault;
    }

    function balanceOfToken() public view override returns (uint256) {
        return 0;
    }

    function invest(uint256 amount) public override {}

    function divest(uint256 amount) public override returns (uint256) {
        return 0;
    }

    function totalLockedValue() public override returns (uint256) {
        return 0;
    }
}

contract VaultTest is TestPlus {
    BaseVault vault;
    MockERC20 token;
    uint8 constant MAX_STRATEGIES = 20;

    function setUp() public {
        vault = Deploy.deployBaseVault();
        token = MockERC20(address(vault.token()));
    }

    function testHarvest() public {
        assertTrue(1 == 1);
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
}
