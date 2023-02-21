// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Vault} from "src/vaults/Vault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {TestStrategy} from "./mocks/TestStrategy.sol";

/// @notice Test common vault functionalities.
contract CommonVaultTest is TestPlus {
    using stdStorage for StdStorage;

    Vault vault;
    MockERC20 asset;

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 6);

        vault = new Vault();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");
    }

    /// @notice Test vault initialization.
    function testInit() public {
        vm.expectRevert();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");

        assertEq(vault.name(), "USD Earn");
        assertEq(vault.symbol(), "usdEarn");
    }

    // Adding this since this test contract is used as a strategy
    function totalLockedValue() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Test post deployment, initial state of the vault.
    function testDeploy() public {
        // this makes sure that the first time we assess management fees we get a reasonable number
        // since management fees are calculated based on block.timestamp - lastHarvest
        assertEq(vault.lastHarvest(), block.timestamp);
    }

    /// @notice Test redeeming after deposit.
    function testDepositRedeem(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        // Running into overflow issues on the call to vault.redeem
        address user = address(this);
        asset.mint(user, amountAsset);

        uint256 expectedShares = uint256(amountAsset) * vault.initialSharesPerAsset();
        // user gives max approval to vault for asset
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, user);

        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(address(user)), 0);

        uint256 assetsReceived = vault.redeem(expectedShares, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(assetsReceived, amountAsset);
    }

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

    /// @notice Test minting vault token.
    function testMint(uint64 amountAsset) public {
        vm.assume(amountAsset > 99);
        address user = address(this);
        asset.mint(user, amountAsset);
        asset.approve(address(vault), type(uint256).max);

        // If vault is empty, assets are converted to shares at 1:vault.initialSharesPerAsset() ratio
        uint256 expectedShares = uint256(amountAsset) * vault.initialSharesPerAsset(); // cast to uint256 to prevent overflow

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amountAsset, expectedShares);
        vault.mint(expectedShares, user);

        assertEq(vault.balanceOf(user), expectedShares);
    }

    /// @notice Test minting zero share results in error.
    function testMinDeposit() public {
        address user = address(this);
        asset.mint(user, 100);
        asset.approve(address(vault), type(uint256).max);

        // If we're minting zero shares we revert
        vm.expectRevert("Vault: zero shares");
        vault.deposit(0, user);

        vault.deposit(100, user);
    }

    /// @notice Test that depositing doesn't result in funds being invested into strategies.
    function testDepositNoStrategyInvest() public {
        address user = address(this);
        uint256 amount = 100;
        asset.mint(user, amount);
        asset.approve(address(vault), type(uint256).max);

        TestStrategy strategy = new TestStrategy(BaseVault(address(vault)));
        vm.startPrank(governance);
        vault.addStrategy(strategy, 10_000);
        vm.stopPrank();

        vault.deposit(amount, user);
        assertEq(asset.balanceOf(address(vault)), amount);

        vm.startPrank(governance);
        uint256 capitalEfficientAmount = 50;
        vault.depositIntoStrategies(capitalEfficientAmount);
        assertEq(asset.balanceOf(address(vault)), amount - capitalEfficientAmount);
        assertEq(vault.vaultTVL(), amount);
        vm.stopPrank();
    }

    /// @notice Test that minting doesn't result in funds being invested into strategies.
    function testMintNoStrategyInvest() public {
        address user = address(this);
        uint256 amount = 100;
        asset.mint(user, amount);
        asset.approve(address(vault), type(uint256).max);

        TestStrategy strategy = new TestStrategy(BaseVault(address(vault)));
        vm.startPrank(governance);
        vault.addStrategy(strategy, 10_000);
        vm.stopPrank();

        vault.mint(amount * vault.initialSharesPerAsset(), user); // Initially asset:share = 1:vault.initialSharesPerAsset().
        assertEq(asset.balanceOf(address(vault)), amount);

        vm.startPrank(governance);
        uint256 capitalEfficientAmount = 50;
        vault.depositIntoStrategies(capitalEfficientAmount);
        assertEq(asset.balanceOf(address(vault)), amount - capitalEfficientAmount);
        assertEq(vault.vaultTVL(), amount);
        vm.stopPrank();
    }

    /// @notice Test management fee is deducted and transferred to governance address.
    function testManagementFee() public {
        // Increase vault's total supply
        deal(address(vault), address(0), 1e18, true);

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
        changePrank(governance);
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);
        vault.setManagementFee(200);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestamp must be >= lastHarvest + LOCK_INTERVAL when harvesting
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        // Call harvest to update lastHarvest, note that no shares are minted here because
        // (block.timestamp - lastHarvest) = LOCK_INTERVAL + 1 =  3 hours + 1 second
        // and feeBps gets truncated to zero
        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        vm.warp(block.timestamp + 365 days / 2);

        // Call harvest to trigger fee assessment
        vault.harvest(strategyList);

        // Check that fees were assesed in the correct amounts => Management fees are sent to governance address
        // 1/2 of 2% of the vault's supply should be minted to governance
        assertEq(vault.balanceOf(governance), (100 * 1e18) / 10_000);
    }

    /// @notice Test profit is locked over the `LOCK_INTERVAL` period.
    function testLockedProfit() public {
        // Add this contract as a strategy
        changePrank(governance);
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestamp must be >= lastHarvest + LOCK_INTERVAL when harvesting
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        asset.mint(address(myStrat), 1e18);
        asset.approve(address(vault), type(uint256).max);

        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        assertEq(vault.lockedProfit(), 1e18);
        assertEq(vault.totalAssets(), 0);

        // Using up 50% of LOCK_INTERVAL unlocks 50% of profit
        vm.warp(block.timestamp + vault.LOCK_INTERVAL() / 2);
        assertEq(vault.lockedProfit(), 1e18 / 2);
        assertEq(vault.totalAssets(), 1e18 / 2);
    }

    /// @notice total assets = vaultTVL() - lockedProfit()
    function testTotalAssets() public {
        // Add this contract as a strategy
        changePrank(governance);
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat, 10_000);

        // Give the strat some assets
        asset.mint(address(vault), 999);

        // Harvest a gain of 1
        asset.mint(address(myStrat), 1);
        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
        vault.harvest(strategyList);

        assertEq(vault.totalAssets(), 999);
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
        assertEq(vault.totalAssets(), 1000);
    }

    /// @notice Test that withdrawal fee is deducted while withdwaring.
    function testWithdrawalFee() public {
        vm.prank(governance);
        vault.setWithdrawalFee(50);

        uint256 amountAsset = 1e18;

        changePrank(alice);
        asset.mint(alice, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, alice);

        vault.redeem(vault.balanceOf(alice), alice, alice);
        assertEq(vault.balanceOf(alice), 0);

        // User gets the original amount with 50bps deducted
        assertEq(asset.balanceOf(alice), (amountAsset * (10_000 - 50)) / 10_000);
        // Governance gets the 50bps fee
        assertEq(asset.balanceOf(vault.governance()), (amountAsset * 50) / 10_000);
    }

    /// @notice Test that goveranance can modify management fees.
    function testSettingFees() public {
        changePrank(governance);
        vault.setManagementFee(300);
        assertEq(vault.managementFee(), 300);
        vault.setWithdrawalFee(10);
        assertEq(vault.withdrawalFee(), 10);

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        vault.setManagementFee(300);
        vm.expectRevert("Only Governance.");
        vault.setWithdrawalFee(10);
    }

    /// @notice Test that goveranance can pause the vault.
    function testVaultPause() public {
        changePrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1e18, address(this), address(this));

        vault.unpause();

        vm.stopPrank();
        testDepositWithdraw(1e18);

        // Only the HARVESTER address can call pause or unpause
        string memory errString = string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role ",
                Strings.toHexString(uint256(vault.GUARDIAN_ROLE()), 32)
            )
        );

        bytes memory errorMsg = abi.encodePacked(errString);

        vm.expectRevert(errorMsg);
        changePrank(alice);
        vault.pause();

        vm.expectRevert(errorMsg);
        vault.unpause();
    }

    /// @notice Test that view functions for detailed price of vault token works.
    function testDetailedPrice() public {
        // This function should work even if there is nothing in the vault
        Vault.Number memory price = vault.detailedPrice();
        assertEq(price.num, 100 * 10 ** uint256(asset.decimals()));

        asset.mint(address(vault), 2e18);

        // initial price is $100, but if we increase tvl the price increases
        Vault.Number memory price2 = vault.detailedPrice();
        assertTrue(price2.num > price.num);
    }
}
