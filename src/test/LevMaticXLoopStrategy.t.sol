// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LevMaticXLoopStrategy, AffineVault, FixedPointMathLib} from "src/strategies/LevMaticXLoopStrategy.sol";
import {LidoLev} from "src/strategies/LidoLev.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";

import {IBalancerVault, IFlashLoanRecipient, IBalancerQueries} from "src/interfaces/balancer.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {console2} from "forge-std/console2.sol";

contract LevMaticXLoopStrategyTest is TestPlus {
    uint256 init_assets;
    AffineVault vault;
    LevMaticXLoopStrategy staking;

    receive() external payable {}

    ERC20 public asset = ERC20((0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270)); // wmatic
    /// @notice The wETH address.
    ERC20 public WMATIC = ERC20(payable(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270));

    /// @notice The wstETH address (actually cbETH on Base).
    ERC20 public STMATIC = ERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4); // eth
    IBalancerVault public BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 public POOL_ID = 0xf0ad209e2e969eaaa8c882aac71f02d8a047d5c2000200000000000000000b49;
    ERC20 public constant MATICX = ERC20(0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6); // polygon
    IPool public constant AAVE = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // polygon address

    function _getVault() internal virtual returns (AffineVault) {
        init_assets = 1 * (10 ** asset.decimals());
        VaultV2 vault_v2 = new VaultV2();
        vault_v2.initialize(governance, address(asset), "TV", "TV");
        return AffineVault(address(vault_v2));
    }

    function setUp() public {
        // fork eth
        // TODO: Fixed block number
        vm.createSelectFork("polygon", 52_299_165);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = _getVault();

        staking = new LevMaticXLoopStrategy(vault, strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 10_000);
    }

    function _getPricePerShare() internal returns (uint256) {
        return VaultV2(address(vault)).detailedPrice().num;
    }

    function testInvestIntoStrategy() public {
        deal(address(asset), alice, init_assets);

        vm.startPrank(alice);
        asset.approve(address(staking), init_assets);
        staking.invest(init_assets);

        console2.log("TVL %s", staking.totalLockedValue());

        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.01e18);
        assertEq(asset.balanceOf(alice), 0);
    }

    function testDivestFull() public {
        testInvestIntoStrategy();

        vm.startPrank(address(vault));
        staking.divest(staking.totalLockedValue());

        assertEq(staking.totalLockedValue(), 0);
        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.01e18);
        console2.log("TVL %s, init Assets %s", vault.vaultTVL(), init_assets);
    }

    function testTryDivestMore() public {
        testInvestIntoStrategy();

        vm.startPrank(address(vault));
        staking.divest(init_assets);

        assertEq(staking.totalLockedValue(), 0);
        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.01e18);
    }

    function testDivestHalf() public {
        testInvestIntoStrategy();

        vm.startPrank(address(vault));
        uint256 sTVL = staking.totalLockedValue();
        uint256 toDivest = sTVL / 2;

        staking.divest(toDivest);

        assertApproxEqAbs(staking.totalLockedValue(), sTVL - toDivest, 0.001e18);
        assertApproxEqRel(vault.vaultTVL(), toDivest, 0.01e18);
    }

    function testDepositToVault() public {
        uint256 prevPricePerShare = _getPricePerShare();
        deal(address(asset), alice, init_assets);

        vm.startPrank(alice);
        asset.approve(address(vault), init_assets);

        VaultV2(address(vault)).deposit(init_assets, alice);

        assertEq(vault.vaultTVL(), init_assets);

        vm.startPrank(governance);

        VaultV2(address(vault)).depositIntoStrategies(init_assets);

        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.001e18);
        assertApproxEqRel(prevPricePerShare, _getPricePerShare(), 0.0001e18);
    }

    function testWithdrawFromVault() public {
        uint256 prevPricePerShare = _getPricePerShare();
        testDepositToVault();

        vm.startPrank(alice);

        assertEq(asset.balanceOf(alice), 0);
        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.001e18);

        VaultV2(address(vault)).withdraw(init_assets, alice, alice);

        assertApproxEqRel(asset.balanceOf(alice), init_assets, 0.01e18);
        assertEq(staking.totalLockedValue(), 0);
        assertApproxEqRel(prevPricePerShare, _getPricePerShare(), 0.0001e18);
    }

    function testWithdrawHalfFromVault() public {
        uint256 prevPricePerShare = _getPricePerShare();
        testDepositToVault();

        vm.startPrank(alice);

        assertEq(asset.balanceOf(alice), 0);
        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.001e18);

        VaultV2(address(vault)).withdraw(init_assets / 2, alice, alice);

        assertApproxEqRel(asset.balanceOf(alice), init_assets / 2, 0.01e18);
        assertApproxEqRel(staking.totalLockedValue(), init_assets / 2, 0.01e18);
        assertApproxEqRel(prevPricePerShare, _getPricePerShare(), 0.0001e18);
    }

    function testUpgradeStrategy() public {
        testInvestIntoStrategy();
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        LevMaticXLoopStrategy new_staking = new LevMaticXLoopStrategy(vault, strategists);
        vm.startPrank(governance);
        vault.addStrategy(new_staking, 0);

        BaseStrategy[] memory strategyList = new BaseStrategy[](2);
        strategyList[0] = BaseStrategy(address(staking));
        strategyList[0] = BaseStrategy(address(new_staking));

        uint16[] memory tvlBpsList = new uint16[](2);
        tvlBpsList[0] = 0;
        tvlBpsList[1] = 10_000;

        uint256 prevTVL = staking.totalLockedValue();
        assertEq(new_staking.totalLockedValue(), 0);

        vault.updateStrategyAllocations(strategyList, tvlBpsList);

        staking.upgradeTo(new_staking);

        assertEq(new_staking.totalLockedValue(), prevTVL);
        assertEq(staking.totalLockedValue(), 0);
    }
}
