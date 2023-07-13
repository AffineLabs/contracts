// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {AffineBadges} from "src/nfts/AffineBadges.sol";
import {LeveragedEthVault} from "src/vaults/LeveragedEthVault.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @notice Test general functionalities of strategies.
contract AffineBadgesTest is TestPlus, IERC1155Receiver {
    LeveragedEthVault vault;
    AffineBadges affineBadges;
    MockERC20 asset;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);
        affineBadges = new AffineBadges();
        vault = new LeveragedEthVault();
        vault.initialize(governance, address(asset), "ETH Earn", "ethEarn");
        vm.startPrank(governance);
        vault.setNFTContractAddress(address(affineBadges));
        vm.stopPrank();
        affineBadges.setMintActive(true);
        affineBadges.setCanMint(address(vault));
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

    /// @notice Test withdawing after deposit and NFT minting.
    function testNftMinting(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        // shares = assets * totalShares / totalAssets but totalShares will actually be bigger than a uint128
        // so the `assets * totalShares` calc will overflow if using a uint128
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        // If vault is empty, assets are converted to shares at 1:vault.initialSharesPerAsset() ratio
        uint256 expectedShares = uint256(amountAsset) * vault.initialSharesPerAsset(); // cast to uint256 to prevent overflow

        // Enable NFT minting
        vm.startPrank(governance);
        vault.enableNFTMinting(true);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, expectedShares);
        assertEq(affineBadges.balanceOf(user, 1), 0);
        vault.deposit(amountAsset, user);
        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(user), 0);
        assertEq(affineBadges.balanceOf(user, 1), 1);
        vault.withdraw(amountAsset, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amountAsset);
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
