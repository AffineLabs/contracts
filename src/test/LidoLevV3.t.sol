// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LidoLevV3, AffineVault, FixedPointMathLib} from "src/strategies/LidoLevV3.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";

import {console2} from "forge-std/console2.sol";

contract LidoLevV3Test is TestPlus {
    uint256 init_assets;
    AffineVault vault;
    LidoLevV3 staking;

    receive() external payable {}

    ERC20 public asset = ERC20((0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    function _getVault() internal virtual returns (AffineVault) {
        init_assets = 1 * (10 ** asset.decimals());
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
}
