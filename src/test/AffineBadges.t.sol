// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {AffineBadges} from "src/nfts/AffineBadges.sol";
import {LeveragedEthVault} from "src/vaults/LeveragedEthVault.sol";

/// @notice Test general functionalities of strategies.
contract BaseStrategyTest is TestPlus {
    LeveragedEthVault vault;
    AffineBadges affineBadges;
    MockERC20 asset;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);
        affineBadges = new AffineBadges();
        vault = new LeveragedEthVault();
        vault.initialize(governance, address(asset), "ETH Earn", "ethEarn");
        vault.setNFTContractAddress(address(affineBadges));
    }

    /// @notice Test vault initialization.
    function testInit() public {
        vm.expectRevert();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");

        assertEq(vault.name(), "ETH Earn");
        assertEq(vault.symbol(), "ethEarn");
    }

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Test withdawing after deposit.
    function testDepositWithdraw(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        // shares = assets * totalShares / totalAssets but totalShares will actually be bigger than a uint128
        // so the `assets * totalShares` calc will overflow if using a uint128
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        // If vault is empty, assets are converted to shares at 1:vault.initialSharesPerAsset() ratio
        uint256 expectedShares = uint256(amountAsset) * vault.initialSharesPerAsset(); // cast to uint256 to prevent overflow

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, expectedShares);
        vault.deposit(amountAsset, user);
        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(user), 0);
        vault.withdraw(amountAsset, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amountAsset);
    }


}
