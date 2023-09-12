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

import {console} from "forge-std/console.sol";

contract MockLidoLev is LidoLevL2 {
    constructor(uint256 _leverage, AffineVault _vault, address[] memory strategists)
        LidoLevL2(_leverage, _vault, strategists)
    {}

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

        staking = new MockLidoLev(992, vault, strategists);
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
        console.log("WETH balance: %s", weth.balanceOf(address(this)));
        console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));
    }

    function testTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 10 ether, 0.01e18);
    }

    function testMutateTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console.log("Orig tvl: ", tvl);
        console.log("orig collateral: ", staking.aToken().balanceOf(address(staking)));
        console.log("orig debt: ", staking.debtToken().balanceOf(address(staking)));

        vm.prank(address(vault));
        staking.divest(1 ether);

        // TODO: Bring this bound down to 1%
        assertApproxEqRel(staking.totalLockedValue(), tvl - 1 ether, 0.1e18);
    }
}
