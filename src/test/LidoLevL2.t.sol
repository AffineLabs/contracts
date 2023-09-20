// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {
    LidoLevL2,
    IBalancerVault,
    IFlashLoanRecipient,
    AffineVault,
    FixedPointMathLib
} from "src/strategies/LidoLevL2.sol";

import {console2} from "forge-std/console2.sol";

contract MockLidoLev is LidoLevL2 {
    constructor(AffineVault _vault, address[] memory strategists) LidoLevL2(_vault, strategists) {}

    function wstEthToEth(uint256 wstEthAmount) external returns (uint256 ethAmount) {
        ethAmount = _wstEthToEth(wstEthAmount);
    }

    function addToPosition(uint256 amount) external {
        _afterInvest(amount);
    }
}

contract LidoLevL2Test is TestPlus {
    using FixedPointMathLib for uint256;

    MockLidoLev staking;
    AffineVault vault;

    receive() external payable {}

    function setUp() public {
        forkBase();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new MockLidoLev(vault, strategists);
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
        _giveEther(10 ether);
        staking.addToPosition(10 ether);
    }

    function testLeverage() public {
        testAddToPosition();
        uint256 aaveCollateral = staking.wstEthToEth(staking.aToken().balanceOf(address(staking)));
        uint256 depSize = 10 ether;
        assertApproxEqRel(aaveCollateral, depSize * 992 / 100, 0.02e18);
    }

    function testClosePosition() public {
        ERC20 weth = staking.WETH();
        testAddToPosition();
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        _divest(1 ether);
        console2.log("WETH balance: %s", weth.balanceOf(address(this)));
        console2.log("WETH staking balance: %s", weth.balanceOf(address(staking)));
    }

    function testTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console2.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 10 ether, 0.01e18);
    }

    function testMutateTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console2.log("Orig tvl: ", tvl);
        console2.log("orig collateral: ", staking.aToken().balanceOf(address(staking)));
        console2.log("orig debt: ", staking.debtToken().balanceOf(address(staking)));

        vm.prank(address(vault));
        staking.divest(1 ether);

        assertApproxEqRel(staking.totalLockedValue(), tvl - 1 ether, 0.01e18);
    }

    function testSetParams() public {
        staking.setLeverage(1000);
        assertEq(staking.leverage(), 1000);

        staking.setBorrowBps(9500);
        assertEq(staking.borrowBps(), 9500);
    }

    function testAddLargeEthAmount() public {
        // AAVE only allows about 500 cbETH as of current block
        uint256 amount = 30 ether;
        _giveEther(amount);
        staking.setSlippageBps(2000);
        staking.setLeverage(955);
        staking.addToPosition(amount);
    }
}
