// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity =0.8.16;

// import {TestPlus} from "src/test/TestPlus.sol";
// import {DefaultCollateral} from "collateral/src/contracts/defaultCollateral/DefaultCollateral.sol";
// import {ERC20} from "solmate/src/tokens/ERC20.sol";

// import {console2} from "forge-std/console2.sol";

// contract TestSymbioticDelegator is TestPlus {
//     ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

//     function setUp() public {
//         vm.createSelectFork("ethereum", 19_771_000);
//         collateral = new DefaultCollateral();
//         collateral.initialize(address(asset), type(uint128).max, type(uint128).max);
//     }

//     function testTemp() public {
//         console2.log("===> test");
//         assertTrue(true);
//     }
// }
