// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StakingExp, IBalancerVault, IFlashLoanRecipient} from "src/strategies/Staking.sol";

contract StakingTest is TestPlus {
    StakingExp staking;

    function setUp() public {
        forkEth();
        staking = new StakingExp(IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8));
    }

    function testFlashLoan() public {
        vm.deal(address(staking), 1.005 ether);
        staking.startPosition(1 ether, 5);
        // ERC20[] memory tokens = new ERC20[](1);
        // tokens[0] = ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
        // uint256[] memory amounts = new uint256[](1);
        // amounts[0] = 1.005 ether;
        // staking.flashLoan(tokens, amounts, "");
    }
}
