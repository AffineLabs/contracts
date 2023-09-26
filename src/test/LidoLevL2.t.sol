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

contract MockLidoLevL2 is LidoLevL2 {
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

    MockLidoLevL2 staking;
    AffineVault vault;

    uint256 depSize = 10 ether;

    receive() external payable {}

    function setUp() public {
        forkBase();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new MockLidoLevL2(vault, strategists);
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
        _giveEther(depSize);
        staking.addToPosition(depSize);
    }

    function testLeverage() public {
        testAddToPosition();
        uint256 aaveCollateral = staking.wstEthToEth(staking.aToken().balanceOf(address(staking)));
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
        assertApproxEqRel(tvl, depSize, 0.01e18);
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
    }

    function testAddLargeEthAmount() public {
        // AAVE only allows about 500 cbETH as of current block
        uint256 amount = 30 ether;
        _giveEther(amount);
        staking.setSlippageBps(2000);
        staking.setLeverage(955);
        staking.addToPosition(amount);
    }

    function testUpgrade() public {
        testAddToPosition();
        uint256 beforeTvl = staking.totalLockedValue();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        MockLidoLevL2 staking2 = new MockLidoLevL2(vault, strategists);
        assertEq(staking2.totalLockedValue(), 0);

        vm.startPrank(governance);
        vault.addStrategy(staking2, 0);
        staking.upgradeTo(staking2);

        // All value was moved to staking2
        assertEq(staking.totalLockedValue(), 0);
        assertEq(staking2.totalLockedValue(), beforeTvl);

        // We can divest in staking2
        vm.startPrank(address(vault));
        staking2.divest(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), beforeTvl - 1 ether, 0.01e18);

        // We can invest in staking2
        deal(address(staking2.WETH()), address(staking2), 1 ether);
        staking2.addToPosition(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), beforeTvl, 0.001e18);
    }
}
