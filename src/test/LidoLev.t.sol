// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LidoLev, IBalancerVault, IFlashLoanRecipient, AffineVault, ICdpManager} from "src/strategies/LidoLev.sol";

import {console} from "forge-std/console.sol";

contract StakingTest is TestPlus {
    LidoLev staking;
    AffineVault vault;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum", 17_687_253);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new LidoLev(LidoLev(payable(address(0))), 175, vault, strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 0);
    }

    function _giveEther(uint256 amount) internal {
        ERC20 weth = staking.WETH();
        deal(address(weth), address(staking), amount);
    }

    function _divest(uint256 amount) internal {
        vm.prank(address(vault));
        staking.divest(amount);
    }

    function testAddToPosition() public {
        _giveEther(30 ether);
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
        assertApproxEqRel(tvl, 30 ether, 0.001e18);
    }

    function testTotalLockedValueII() public {
        _giveEther(7 ether);
        staking.addToPosition(7 ether);
        uint256 tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 7 ether, 0.001e18);
    }

    function testMutateTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();

        deal(address(staking.WETH()), address(this), 1 ether);
        staking.WETH().transfer(address(staking), 1 ether);

        assertApproxEqRel(staking.totalLockedValue(), tvl + 1 ether, 0.001e18);

        vm.prank(address(vault));
        staking.divest(1 ether);
        assertApproxEqRel(staking.totalLockedValue(), tvl, 0.001e18);
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
        _giveEther(10 ether);
        vm.expectRevert();
        staking.addToPosition(1 ether);

        staking.addToPosition(7 ether);
    }

    function testUpgrade() public {
        testAddToPosition();
        uint256 beforeTvl = staking.totalLockedValue();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        LidoLev staking2 = new LidoLev(staking, 175, vault, strategists);

        vm.prank(governance);
        staking.upgrade(address(staking2));

        // Cdp was transferred
        assertEq(staking.cdpId(), staking2.cdpId());
        assertEq(staking.urn(), staking2.urn());

        // All value was moved to staking2
        assertEq(staking.totalLockedValue(), 0);
        assertEq(staking2.totalLockedValue(), beforeTvl);

        // We can divest in staking2
        vm.prank(address(vault));
        staking2.divest(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), 29 ether, 0.001e18);

        // We can invest in staking2
        // Dealing to staking2 directly will overwrite any weth dust and slighlty reduce the tvl
        deal(address(staking2.WETH()), address(this), 1 ether);
        ERC20(staking2.WETH()).transfer(address(staking2), 1 ether);
        staking2.addToPosition(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), 30 ether, 0.001e18);
    }
}
