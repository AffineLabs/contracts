// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import "forge-std/console2.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestPlus} from "../TestPlus.sol";

contract DegenImplTest is TestPlus {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // function setUp() public {
    //     forkPolygon();
    // }

    function testImpl() public {
        vm.createSelectFork("polygon", 42_754_895);
        address degenVault = 0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46;
        bytes32 implBytes = vm.load(degenVault, _IMPLEMENTATION_SLOT);

        address implAddr = address(uint160(uint256(implBytes)));
        console2.log("impl", implAddr);
    }
}
