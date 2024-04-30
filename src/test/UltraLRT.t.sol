// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Vault, ERC721, VaultErrors} from "src/vaults/Vault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {BaseVault} from "src/vaults/cross-chain-vault/audited/BaseVault.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";

import {console2} from "forge-std/console2.sol";

contract UltraLRTTest is TestPlus {
    UltraLRT vault;
    ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    uint256 initAssets;

    function setUp() public {
        vm.createSelectFork("ethereum", 19_770_000);
        vault = new UltraLRT();

        AffineDelegator delegator = new AffineDelegator();

        // d
        vault.initialize(governance, address(asset), address(delegator), "uLRT", "uLRT");
        initAssets = 10 ** asset.decimals();
        initAssets *= 100;
    }

    function _getAsset(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        IStEth(address(asset)).submit{value: amount}(address(0));
        return asset.balanceOf(to);
    }

    function testDeposit() public {
        uint256 stEth = _getAsset(alice, initAssets);
        vm.prank(alice);
        asset.approve(address(vault), stEth);
        vm.prank(alice);
        vault.deposit(stEth, alice);

        console2.log("vault balance %s", vault.balanceOf(alice));

        assertEq(vault.balanceOf(alice), stEth * 1e8);
    }

    function testWithdrawFull() public {
        testDeposit();
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.convertToAssets(shares);

        vm.prank(alice);
        vault.withdraw(assets, alice, alice);

        // alice st eth balance
        assertEq(asset.balanceOf(alice), assets);
        assertEq(vault.totalSupply(), 0);
    }
}
