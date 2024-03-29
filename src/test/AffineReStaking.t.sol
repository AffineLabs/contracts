// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {AffineReStaking} from "src/vaults/restaking/AffineReStaking.sol";
import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

import {console2} from "forge-std/console2.sol";

contract AffineReStakingV2 is AffineReStaking {
    function version() external pure returns (uint256) {
        return 100;
    }
}

contract AffineReStakingTest is TestPlus {
    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 ezEth = ERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);
    ERC20 matic = ERC20(0xAdf829f541a57Ef2af4d8A07a7920F7229684dDA);
    uint256 init_assets;
    AffineReStaking reStaking;

    function setUp() public virtual {
        vm.createSelectFork("ethereum");

        AffineReStaking impl = new AffineReStaking();

        bytes memory initData = abi.encodeCall(AffineReStaking.initialize, (governance, address(weth)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        reStaking = AffineReStaking(address(proxy));
        // approve ez eth
        // vm.prank(governance);
        // reStaking.approveToken(address(ezEth));

        init_assets = 100 * (10 ** ezEth.decimals());
    }

    function _giveERC20(address token, address user, uint256 amount) internal {
        deal(token, user, amount);
    }

    function testDeposit() public {
        _giveERC20(address(ezEth), alice, init_assets);
        vm.startPrank(alice);
        ezEth.approve(address(reStaking), init_assets);
        reStaking.depositFor(address(ezEth), alice, init_assets);

        assertEq(reStaking.balance(address(ezEth), alice), init_assets);
    }

    function testWithdrawal() public {
        testDeposit();
        reStaking.withdraw(address(ezEth), init_assets);

        assertEq(reStaking.balance(address(ezEth), alice), 0);
        assertEq(ezEth.balanceOf(alice), init_assets);
    }

    // function testDepositNotApprovedToken() public {
    //     _giveERC20(address(weth), alice, init_assets);
    //     vm.startPrank(alice);
    //     weth.approve(address(reStaking), init_assets);
    //     vm.expectRevert(ReStakingErrors.TokenNotAllowedForStaking.selector);
    //     reStaking.depositFor(address(weth), alice, init_assets);
    // }

    function testPauseDeposit() public {
        vm.prank(governance);
        reStaking.pauseDeposit();

        _giveERC20(address(ezEth), alice, init_assets);
        vm.startPrank(alice);
        ezEth.approve(address(reStaking), init_assets);
        vm.expectRevert();
        reStaking.depositFor(address(weth), alice, init_assets);
    }

    function testUpgrade() public {
        testDeposit();

        AffineReStakingV2 impl = new AffineReStakingV2();

        vm.startPrank(governance);
        reStaking.upgradeTo(address(impl));

        assertEq(reStaking.balance(address(ezEth), alice), init_assets);
        assertEq(AffineReStakingV2(address(reStaking)).version(), uint256(100));
    }

    // function testDepositEthWithoutApproval() public {
    //     // get ether
    //     console2.log("eth balance ", alice.balance);
    //     vm.deal(alice, 10 ether);
    //     console2.log("eth balance ", alice.balance);

    //     vm.prank(alice);
    //     vm.expectRevert(ReStakingErrors.TokenNotAllowedForStaking.selector);
    //     reStaking.depositETHFor{value: 10 ether}(alice);
    //     console2.log("eth balance ", alice.balance);
    //     assertEq(alice.balance, 10 ether);
    // }

    // function testDepositEthWithApproval() public {
    //     // approve weth
    //     vm.prank(governance);
    //     reStaking.approveToken(address(weth));
    //     // get ether
    //     console2.log("eth balance ", alice.balance);
    //     vm.deal(alice, 10 ether);
    //     console2.log("eth balance ", alice.balance);

    //     vm.prank(alice);
    //     reStaking.depositETHFor{value: 10 ether}(alice);
    //     console2.log("eth balance ", alice.balance);

    //     // check alice eth balance
    //     assertEq(alice.balance, 0);
    //     // check weth balance of contract
    //     assertEq(weth.balanceOf(address(reStaking)), 10 ether);
    //     // check alice balance in contract
    //     assertEq(reStaking.balance(address(weth), alice), 10 ether);
    // }

    function testFailWithdrawAfterPaused() public {
        testDeposit();
        // pause
        vm.startPrank(governance);
        reStaking.pause();
        vm.startPrank(alice);
        reStaking.withdraw(address(ezEth), reStaking.balance(address(ezEth), alice));
    }

    function testWithdrawWhenDepositPaused() public {
        testDeposit();
        // pause
        vm.startPrank(governance);
        reStaking.pauseDeposit();
        vm.startPrank(alice);
        reStaking.withdraw(address(ezEth), reStaking.balance(address(ezEth), alice));

        assertEq(ezEth.balanceOf(alice), init_assets);
    }
}
