// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {EthVault} from "src/vaults/EthVault.sol";

contract EthVaultTest is TestPlus {
    EthVault vault;
    ERC20 asset;

    function setUp() public {
        forkEth();

        asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vault = new EthVault();
        vault.initialize(governance, address(asset), "Eth Earn", "ethEarn");
    }

    function testWithdrawEth() public {
        // Give alice 1 share (in vault's decimals)
        uint256 shares = 10 ** vault.decimals();
        deal(address(vault), alice, shares, true);
        // Give vault 1 WETH
        deal(vault.asset(), address(vault), 1e18);

        // Alice withdraws 1 ether
        vm.prank(alice);
        vault.withdraw(1 ether, alice, alice);

        // Alice receives 1 ether and has no shares or WETH
        assertEq(alice.balance, 1 ether);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(vault.balanceOf(alice), 0);
    }
    /// @notice Test redeem eth

    function testRedeemEth() public {
        // Give alice 1 share (in vault's decimals)
        uint256 shares = 10 ** vault.decimals();
        deal(address(vault), alice, shares, true);
        // Give vault 1 WETH
        deal(vault.asset(), address(vault), 1e18);

        // Alice withdraws 1 ether
        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        // Alice receives 1 ether and has no shares or WETH
        assertEq(alice.balance, 1 ether);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(vault.balanceOf(alice), 0);
    }
}
