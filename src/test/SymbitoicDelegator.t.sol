// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";
import {DefaultCollateral} from "src/test/mocks/SymCollateral.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

import {console2} from "forge-std/console2.sol";

contract TestSymbioticDelegator is TestPlus {
    ERC20 asset = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // wrapped staked eth
    DefaultCollateral collateral;
    SymbioticDelegator delegator;
    UltraLRT vault;
    uint256 initialAmount;

    function setUp() public {
        vm.createSelectFork("ethereum", 19_771_000);
        collateral = new DefaultCollateral();
        collateral.initialize(address(asset), type(uint128).max, governance);

        //
        vault = new UltraLRT();

        SymbioticDelegator delImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delImpl), governance);

        vault.initialize(governance, address(asset), address(beacon), "Symbiotic uLRT", "uLRT-SYM");

        delegator = new SymbioticDelegator();
        delegator.initialize(address(vault), address(collateral));

        initialAmount = 100 * (10 ** asset.decimals());
    }

    function _getAsset(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }

    function testDeposit() public {
        _getAsset(address(asset), address(vault), initialAmount);

        vm.prank(address(vault));
        asset.approve(address(delegator), initialAmount);

        // revert
        vm.expectRevert();
        delegator.delegate(initialAmount);

        vm.prank(address(vault));
        delegator.delegate(initialAmount);

        assertEq(delegator.totalLockedValue(), initialAmount);
        assertEq(delegator.withdrawableAssets(), initialAmount);
        assertEq(delegator.queuedAssets(), 0);
    }

    function testWithdrawal() public {
        testDeposit();
        // withdraw without harvester
        vm.expectRevert();
        delegator.requestWithdrawal(initialAmount);

        vm.prank(address(vault));
        delegator.requestWithdrawal(initialAmount);

        assertEq(delegator.queuedAssets(), initialAmount);
        // not a vault
        vm.expectRevert();
        delegator.withdraw();

        vm.prank(address(vault));
        delegator.withdraw();

        assertEq(asset.balanceOf(address(vault)), initialAmount);
    }

    function testInvalidCollateral() public {
        DefaultCollateral tmpCol = new DefaultCollateral();
        tmpCol.initialize(address(vault), type(uint128).max, governance);

        SymbioticDelegator delImpl = new SymbioticDelegator();

        vm.expectRevert();
        delImpl.initialize(address(vault), address(tmpCol));
    }
}
