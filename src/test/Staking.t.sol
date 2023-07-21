// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StakingExp, IBalancerVault, IFlashLoanRecipient, AffineVault, ICdpManager} from "src/strategies/Staking.sol";

import {console} from "forge-std/console.sol";

contract StakingTest is TestPlus {
    StakingExp staking;
    AffineVault vault;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum", 17_687_253);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new StakingExp(175, vault, strategists);
    }

    function _giveEther() internal {
        ERC20 weth = staking.WETH();
        deal(address(weth), address(staking), 30.3 ether);
    }

    function _divest(uint256 amount) internal {
        vm.prank(address(vault));
        staking.divest(amount);
    }

    function testAddToPosition() public {
        _giveEther();
        staking.addToPosition(30 ether);
    }

    function testClosePosition() public {
        ERC20 weth = staking.WETH();
        testAddToPosition();
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        _divest(1 ether);
        console.log("WETH balance: %s", weth.balanceOf(address(this)));
        console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));
    }

    function testTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 30 ether, 0.02e18); // TODO: consider making this bound tighter than 2%
    }

    function testMakerCompDivergence() public {
        testAddToPosition();

        uint256 compDai = staking.CDAI().balanceOfUnderlying(address(staking));
        uint256 makerDai = (compDai * 101) / 100; // Maker debt is 1% higher than Compound collateral

        ICdpManager maker = staking.MAKER();
        address urn = maker.urns(staking.cdpId());
        (uint256 wstCollat,) = staking.VAT().urns(staking.ILK(), urn);

        vm.mockCall(
            address(staking.VAT()),
            abi.encodeCall(staking.VAT().urns, (staking.ILK(), urn)),
            abi.encode(wstCollat, makerDai)
        );

        // vm.warp(block.timestamp + 1 days);
        // vm.roll(block.number + 1);
        _divest(1 ether);

        // TODO: this working, but add some asserts
    }

    function testMinDepositAmt() public {
        _giveEther();
        vm.expectRevert();
        staking.addToPosition(1 ether);

        staking.addToPosition(7 ether);
    }
}
