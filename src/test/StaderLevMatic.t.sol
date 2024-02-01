// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StaderLevMaticStrategy, AffineVault, FixedPointMathLib} from "src/strategies/StaderLevMaticStrategy.sol";
import {LidoLev} from "src/strategies/LidoLev.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";

import {IBalancerVault, IFlashLoanRecipient, IBalancerQueries} from "src/interfaces/balancer.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {console2} from "forge-std/console2.sol";

contract StaderLevMaticTest is TestPlus {
    uint256 init_assets;
    AffineVault vault;
    StaderLevMaticStrategy staking;

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

        staking = new StaderLevMaticStrategy(vault, strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 10_000);
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
        staking.divest(staking.totalLockedValue() / 2);

        assertApproxEqAbs(staking.totalLockedValue(), init_assets / 2, 0.01e18);
        assertApproxEqRel(vault.vaultTVL(), init_assets / 2, 0.01e18);
    }

    function testDepositToVault() public {
        deal(address(asset), alice, init_assets);

        vm.startPrank(alice);
        asset.approve(address(vault), init_assets);

        VaultV2(address(vault)).deposit(init_assets, alice);

        assertEq(vault.vaultTVL(), init_assets);

        vm.startPrank(governance);

        VaultV2(address(vault)).depositIntoStrategies(init_assets);

        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.01e18);
    }

    function testWithdrawFromVault() public {
        testDepositToVault();

        vm.startPrank(alice);

        assertEq(asset.balanceOf(alice), 0);
        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.01e18);

        VaultV2(address(vault)).withdraw(init_assets, alice, alice);

        assertApproxEqRel(asset.balanceOf(alice), init_assets, 0.01e18);
        assertEq(staking.totalLockedValue(), 0);
    }

    function testWithdrawHalfFromVault() public {
        testDepositToVault();

        vm.startPrank(alice);

        assertEq(asset.balanceOf(alice), 0);
        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.01e18);

        VaultV2(address(vault)).withdraw(init_assets / 2, alice, alice);

        assertApproxEqRel(asset.balanceOf(alice), init_assets / 2, 0.01e18);
        assertApproxEqRel(staking.totalLockedValue(), init_assets / 2, 0.01e18);
    }

    function testSlippageBpsChange() public {
        testInvestIntoStrategy();
        vm.startPrank(address(this));

        uint256[6] memory borrowBps = [uint256(8000), 7000, 6000, 5000, 8900, 5000];

        for (uint256 i = 0; i < borrowBps.length; i++) {
            staking.setBorrowBps(borrowBps[i]);
            staking.rebalance();
            console2.log("TVL ratio %s", staking.getLTVRatio());
            assertApproxEqRel(borrowBps[i], staking.getLTVRatio(), 0.05e18);
            assertEq(address(staking).balance, 0);
        }
    }

    function testMutexInvalidLoanOriginator() public {
        testInvestIntoStrategy();

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WMATIC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = init_assets * 9;
        // check balancer flash loan
        vm.expectRevert();
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(staking)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(StaderLevMaticStrategy.LoanType.upgrade, address(this))
        });

        vm.expectRevert();
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(WMATIC);

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        // check aave flash loan
        AAVE.flashLoan({
            receiverAddress: address(this),
            assets: _tokens,
            amounts: amounts,
            interestRateModes: modes,
            onBehalfOf: address(this),
            params: abi.encode(StaderLevMaticStrategy.LoanType.upgrade, address(this)),
            referralCode: 0
        });
    }

    function testInvalidFlashLoan() public {
        testInvestIntoStrategy();
        vm.startPrank(address(this));
        staking.setBorrowBps(9500);
        vm.expectRevert();
        staking.rebalance();
        staking.setBorrowBps(700);
        staking.rebalance();
    }

    function testUpgradeStrategy() public {
        testInvestIntoStrategy();
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        StaderLevMaticStrategy new_staking = new StaderLevMaticStrategy(vault, strategists);
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

    function testUpgradeWithInvalidStrategy() public {
        testInvestIntoStrategy();
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        StaderLevMaticStrategy new_staking = new StaderLevMaticStrategy(vault, strategists);

        vm.expectRevert();
        staking.upgradeTo(new_staking);
    }

    function testFlashLoanWithValidStrategy() public {
        testInvestIntoStrategy();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        StaderLevMaticStrategy new_staking = new StaderLevMaticStrategy(vault, strategists);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WMATIC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = init_assets * 9;

        vm.expectRevert("SLMS: Invalid FL origin");
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(staking)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(StaderLevMaticStrategy.LoanType.upgrade, address(new_staking))
        });
    }
}
