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
    }

    function testTemp() public {
        console2.log("===> test");
        assertTrue(true);
    }
}
