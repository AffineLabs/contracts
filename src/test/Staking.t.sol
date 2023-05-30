// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StakingExp, IBalancerVault, IFlashLoanRecipient} from "src/strategies/Staking.sol";

import {console} from "forge-std/console.sol";

contract StakingTest is TestPlus {
    StakingExp staking;

    receive() external payable {}

    function setUp() public {
        // forkEth();
        vm.createSelectFork("ethereum", 17_337_424);

        staking = new StakingExp(IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8), address(this));
    }

    function testFlashLoan() public {
        vm.deal(address(staking), 1.005 ether);
        staking.startPosition(1 ether, 5, 9);
        staking.endPosition();

        console.logInt(staking.lastPosPnl());
    }

    function testWithdraw() public {
        vm.deal(address(staking), 1 ether);
        staking.withdrawEth(1 ether, alice);
        assertEq(alice.balance, 1 ether);
        assertEq(address(staking).balance, 0);
    }
}
