// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StakingExp, IBalancerVault, IFlashLoanRecipient, AffineVault, ICdpManager} from "src/strategies/Staking.sol";

import {console} from "forge-std/console.sol";

contract StakingTest is TestPlus {
    StakingExp staking;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum",  17687253);

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

    function testClosePosition() public {
        ERC20 weth = staking.WETH();
        testOpenPosition();
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        staking.endPosition(1 ether);
        console.log("WETH balance: %s", weth.balanceOf(address(this)));
        console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));
    }

    function testTotalLockedValue() public {
        testOpenPosition();
        uint tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 30 ether, 0.02e18); // TODO: consider making this bound tighter than 2%
    }

    function testMakerCompDivergence() public {
        testOpenPosition();

        uint compDai = staking.cDAI().balanceOfUnderlying(address(staking));
        uint makerDai = (compDai * 101)  / 100; // Maker debt is 1% higher than Compound collateral

        ICdpManager maker = staking.MAKER();
        address urn = maker.urns(staking.cdpId());
        (uint wstCollat, ) = staking.VAT().urns(staking.ilk(), urn);
        
        vm.mockCall(
        address(staking.VAT()),
        abi.encodeCall(staking.VAT().urns, (staking.ilk(), urn)), 
        abi.encode(wstCollat, makerDai)
        );

        // vm.warp(block.timestamp + 1 days);
        // vm.roll(block.number + 1);
        staking.endPosition(1 ether);

        // TODO: this working, but add some asserts
    }
}
