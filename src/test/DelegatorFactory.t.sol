// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {DelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";
import {SymDelegatorFactory} from "src/vaults/restaking/SymDelegatorFactory.sol";
import {DefaultCollateral} from "src/test/mocks/SymCollateral.sol";

import {TestPlus} from "src/test/TestPlus.sol";

contract TestDelegatorFactory is TestPlus {
    UltraLRT public vault;

    address asset = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;
    address collateral;

    function setUp() public virtual {
        vm.createSelectFork("ethereum", 19_771_000);
        // deploy UltraLR
        vault = new UltraLRT();
        collateral = address(new DefaultCollateral());
        DefaultCollateral(collateral).initialize(asset, type(uint256).max, governance);
    }

    function _initWithEigenDelegator() internal {
        // deploy UltraLRT
        EigenDelegator delegatorImpl = new EigenDelegator();
        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        vault.initialize(governance, address(asset), address(beacon), "uLRT", "uLRT");
    }

    function _initWithSymDelegator() internal {
        // deploy UltraLRT
        SymbioticDelegator delegatorImpl = new SymbioticDelegator();
        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        vault.initialize(governance, address(asset), address(beacon), "uLRT", "uLRT");
    }

    function testEigenDelegatorFactory() public {
        _initWithEigenDelegator();
        // set
        // deploy DelegatorFactory
        DelegatorFactory df = new DelegatorFactory(address(vault));
        // create a new delegator

        vm.prank(governance);
        vault.setDelegatorFactory(address(df));

        address delegator;
        // // @dev should be called by vault only
        vm.expectRevert();
        delegator = df.createDelegator(operator);

        // // create a new delegator
        vm.prank(address(vault));
        delegator = df.createDelegator(operator);
        assertTrue(delegator != address(0));
    }

    function testSymbioticDelegatorFactory() public {
        _initWithSymDelegator();
        // set
        // deploy DelegatorFactory
        SymDelegatorFactory df = new SymDelegatorFactory(address(vault));
        // create a new delegator

        vm.prank(governance);
        vault.setDelegatorFactory(address(df));

        address delegator;
        // @dev should be called by vault only
        vm.expectRevert();
        delegator = df.createDelegator(collateral);

        // create a new delegator
        vm.prank(address(vault));
        delegator = df.createDelegator(collateral);
        assertTrue(delegator != address(0));
    }
}
