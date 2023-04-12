// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {Vault} from "src/vaults/Vault.sol";
import {SingleStrategyWithdrawalEscrow} from "src/vaults/SingleStrategyWithdrawal.sol";

contract SingleStrategyWithdrawalTest is TestPlus {
    Vault vault;
    ERC20 asset;
    SingleStrategyWithdrawalEscrow withdrawalEscrow;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);
        vault = new Vault();
        vault.initialize(governance, address(asset), "Test Vault", "TV");
        withdrawalEscrow = new SingleStrategyWithdrawalEscrow(vault);
    }

    function testInit() public {
        assertTrue(true);
    }
}
