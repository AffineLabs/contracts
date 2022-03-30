// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { BaseStrategy } from "../BaseStrategy.sol";
import { BaseVault } from "../BaseVault.sol";

contract VaultTest is DSTestPlus {
    BaseVault vault;
    MockERC20 token;

    function setUp() public {
        vault = Deploy.deployBaseVault();
        token = MockERC20(address(vault.token()));
    }

    function testHarvest() public {
        assertTrue(1 == 1);
    }
}
