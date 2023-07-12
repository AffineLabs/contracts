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
        vm.createSelectFork("ethereum", 17673841);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        AffineVault vault = AffineVault(address(deployL1Vault()));

        staking = new StakingExp(vault, strategists, IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8), 175);
    }

    function testOpenPosition() public {
        ERC20 weth = staking.WETH();
        deal(address(weth), address(this), 100 ether);
        weth.approve(address(staking), 100 ether);
        staking.startPosition(30 ether, 30.3 ether);

    }

    // function testFlashLoan() public {
    //     ERC20 weth = staking.WETH();
    //     deal(address(weth), address(this), 100 ether);
    //     weth.approve(address(staking), 100 ether);
    //     staking.startPosition(30 ether, 30.3 ether);

    //     console.log("WETH balance: %s", weth.balanceOf(address(this)));
    //     console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));

    //     console.log("TVL: , %s", staking.totalLockedValue());

    //     vm.warp(block.timestamp + 1 days);
    //     vm.roll(block.number + 1);
    //     staking.endPosition(1 ether);
    //     console.log("WETH balance: %s", weth.balanceOf(address(this)));
    //     console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));

    // }


}
