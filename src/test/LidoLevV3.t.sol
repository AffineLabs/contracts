// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LidoLevV3, AffineVault, FixedPointMathLib} from "src/strategies/LidoLevV3.sol";
import {LidoLev} from "src/strategies/LidoLev.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {IBalancerVault, IFlashLoanRecipient} from "src/interfaces/balancer.sol";

import {console2} from "forge-std/console2.sol";

contract LidoLevV3Test is TestPlus {
    uint256 init_assets;
    AffineVault vault;
    LidoLevV3 staking;

    receive() external payable {}

    ERC20 public asset = ERC20((0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    ERC20 public constant WETH = ERC20(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    function _getVault() internal virtual returns (AffineVault) {
        init_assets = 10 * (10 ** asset.decimals());
        VaultV2 vault_v2 = new VaultV2();
        vault_v2.initialize(governance, address(asset), "TV", "TV");
        return AffineVault(address(vault_v2));
    }

    function setUp() public {
        // fork eth
        // TODO: Fixed block number
        vm.createSelectFork("ethereum", 18_600_000);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = _getVault();

        staking = new LidoLevV3(vault, strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 10_000);
    }

    function testInvestIntoStrategy() public {
        deal(address(asset), alice, init_assets);

        vm.startPrank(alice);
        asset.approve(address(staking), init_assets);
        staking.invest(init_assets);

        assertApproxEqRel(staking.totalLockedValue(), init_assets, 0.01e18);
        assertEq(asset.balanceOf(alice), 0);
    }

    function testDivestFull() public {
        testInvestIntoStrategy();

        vm.startPrank(address(vault));
        staking.divest(staking.totalLockedValue());

        assertEq(staking.totalLockedValue(), 0);
        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.01e18);
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
        console2.log(staking.getLTVRatio());
        vm.startPrank(address(this));

        uint256[6] memory borrowBps = [uint256(8000), 7000, 6000, 5000, 8900, 5000];

        for (uint256 i = 0; i < borrowBps.length; i++) {
            staking.setBorrowBps(borrowBps[i]);
            staking.rebalance();
            assertApproxEqRel(borrowBps[i], staking.getLTVRatio(), 0.01e18);
            assertEq(asset.balanceOf(address(staking)), 0);
            assertEq(address(staking).balance, 0);
        }
    }

    function testMutexInvalidLoanOriginator() public {
        testInvestIntoStrategy();

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = init_assets * 9;

        vm.expectRevert();
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(staking)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LidoLevV3.LoanType.upgrade, address(this))
        });

        vm.expectRevert();
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(staking)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LidoLevV3.LoanType.divest, address(this))
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

        LidoLevV3 new_staking = new LidoLevV3(vault, strategists);
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

        LidoLevV3 new_staking = new LidoLevV3(vault, strategists);

        vm.expectRevert();
        staking.upgradeTo(new_staking);
    }

    function testFlashLoanWithValidStrategy() public {
        testInvestIntoStrategy();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        LidoLevV3 new_staking = new LidoLevV3(vault, strategists);

        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = init_assets * 9;

        vm.expectRevert("LLV3: Invalid FL origin");
        BALANCER.flashLoan({
            recipient: IFlashLoanRecipient(address(staking)),
            tokens: tokens,
            amounts: amounts,
            userData: abi.encode(LidoLevV3.LoanType.upgrade, address(new_staking))
        });
    }
}

/// @dev test integration with existing vault
contract LidoLevV3IntegrationTest is TestPlus {
    uint256 init_assets;
    AffineVault vault;
    LidoLevV3 staking;

    receive() external payable {}

    ERC20 public asset = ERC20((0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    function _getVault() internal virtual returns (AffineVault) {
        return AffineVault(0x1196B60c9ceFBF02C9a3960883213f47257BecdB);
    }

    function setUp() public {
        // fork eth
        // TODO: Fixed block number
        vm.createSelectFork("ethereum", 18_600_000);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = _getVault();

        staking = new LidoLevV3(vault, strategists);
    }

    function testAddStrategyRebalance() public {
        // make existing strategy tvl bps to zero
        vm.startPrank(vault.governance());
        uint256 oldTVL = vault.vaultTVL();
        BaseStrategy[] memory strategy = new BaseStrategy[](1);
        uint16[] memory tvlBps = new uint16[](1);

        strategy[0] = BaseStrategy(0x1CB640332F9ADa32Da40053634Cc61335e935995);
        tvlBps[0] = 0;

        vault.updateStrategyAllocations(strategy, tvlBps);
        vault.addStrategy(staking, 10_000);

        // rebalance
        vault.rebalance();
        console2.log("base strategy tvl %s", strategy[0].totalLockedValue());
        assertApproxEqRel(vault.vaultTVL(), oldTVL, 0.01e18);
        // assertApproxEqRel(vault.vaultTVL(), staking.totalLockedValue(), 0.01e18);
    }

    function testInvestExistingStrategyAndWithdraw() public {
        vm.startPrank(vault.governance());
        uint256 oldTVL = vault.vaultTVL();
        BaseStrategy[] memory strategy = new BaseStrategy[](1);
        uint16[] memory tvlBps = new uint16[](1);

        LidoLev oldStrat = LidoLev(payable(0x1CB640332F9ADa32Da40053634Cc61335e935995));
        uint256 stratTVL = asset.balanceOf(address(oldStrat));
        console2.log(
            "Old strategy balance %s and TVL ", asset.balanceOf(address(oldStrat)), oldStrat.totalLockedValue()
        );

        oldStrat.sweep(asset);

        asset.transfer(address(vault), stratTVL);

        strategy[0] = BaseStrategy(0x1CB640332F9ADa32Da40053634Cc61335e935995);
        tvlBps[0] = 0;

        vault.updateStrategyAllocations(strategy, tvlBps);
        vault.harvest(strategy);

        vault.addStrategy(staking, 10_000);

        vault.rebalance();
        console2.log("base strategy tvl %s", strategy[0].totalLockedValue());
        assertApproxEqRel(vault.vaultTVL(), oldTVL, 0.01e18);
        assertApproxEqRel(vault.vaultTVL(), staking.totalLockedValue(), 0.01e18);
    }
}
