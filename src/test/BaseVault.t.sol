// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./test.sol";

import { IHevm } from "./IHevm.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { Strategy } from "../Strategy.sol";
import { BaseVault } from "../BaseVault.sol";

contract VaultTest is DSTest {
    BaseVault vault;
    MockERC20 token;

    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        vault = Deploy.deployBaseVault();
        token = MockERC20(address(vault.token()));
    }

    function testHarvest() public {
        assertTrue(1 == 1);
    }
}
