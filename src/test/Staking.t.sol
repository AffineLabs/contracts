// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StakingExp, IBalancerVault, IFlashLoanRecipient, AffineVault} from "src/strategies/Staking.sol";

import {console} from "forge-std/console.sol";

contract StakingTest is TestPlus {
    StakingExp staking;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum", 17414444);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        
        AffineVault vault = AffineVault(address(deployL1Vault()));

        staking = new StakingExp(vault, strategists, IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8), 175);
    }

    function testFlashLoan() public {
        vm.deal(address(staking), 100 ether);
        staking.startPosition(30 ether, 5);
        // staking.endPosition();

        // console.logInt(staking.lastPosPnl());
    }

}
