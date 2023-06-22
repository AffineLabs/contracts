// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";
import {Vault} from "src/vaults/Vault.sol";

import {TestStrategy} from "./mocks/TestStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";

// TODO: merge with CommonVaultTest
import {CommonVaultTest} from "./Vault.t.sol";

contract SVaultTest is TestPlus {
    using stdStorage for StdStorage;

    StrategyVault vault;
    MockERC20 asset;
    MockEpochStrategy strategy;

    function forkNet() public virtual {}

    function setUp() public {
        forkNet();
        asset = new MockERC20("Mock", "MT", 6);

        vault = new StrategyVault();
        vault.initialize(governance, address(asset), "USD Earn", "usdEarn");

        WithdrawalEscrow escrow = new WithdrawalEscrow(vault);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        strategy = new MockEpochStrategy(vault, strategists);
        vm.startPrank(governance);
        vault.setStrategy(strategy);
        vault.setDebtEscrow(escrow);
        vault.setTvlCap(type(uint256).max);
        vault.grantRole(vault.HARVESTER(), address(this));
        vault.grantRole(vault.GUARDIAN_ROLE(), address(this));
        vm.stopPrank();
    }

    event Upgraded(address indexed implementation);

    function testCanUpgrade() public {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (governance, address(asset), "Affine High Yield LP - USDC-wETH", "affineSushiUsdcWeth")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        StrategyVault sVault = StrategyVault(address(proxy));

        StrategyVault impl2 = new StrategyVault();

        vm.expectRevert("Only Governance.");
        sVault.upgradeTo(address(impl2));

        vm.prank(governance);
        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(impl2));
        sVault.upgradeTo(address(impl2));
    }

    function testStrategyGetsAllDeposits() public {
        asset.mint(address(this), 1000);
        asset.approve(address(vault), type(uint256).max);

        vault.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(strategy)), 1000);
    }

    function testTvlCap() public {
        vm.prank(governance);
        vault.setTvlCap(1000);

        asset.mint(address(this), 2000);
        asset.approve(address(vault), type(uint256).max);

        vault.deposit(500, address(this));
        assertEq(asset.balanceOf(address(this)), 1500);

        // We only deposit 500 because the limit is 500 and 500 is already in the vault
        vault.deposit(1000, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);

        vm.expectRevert("Vault: deposit limit reached");
        vault.deposit(200, address(this));
        assertEq(asset.balanceOf(address(this)), 1000);
    }

    /// @notice Test
    function testLockedProfitAfterEpoch() public {
        // Begin epoch
        strategy.beginEpoch();

        // Mint gain and endEpoch
        strategy.endEpoch();

        // All gains are locked
        assertEq(vault.lockedProfit(), 1e6);

        // Half of gains unlock after half of lock interval passes
        vm.warp(block.timestamp + vault.LOCK_INTERVAL() / 2);
        assertEq(vault.lockedProfit(), 1e6 / 2);
        assertEq(vault.totalAssets(), 1e6 / 2);
    }

    /*//////////////////////////////////////////////////////////////
                         BASIC VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Test management fee is deducted and transferred to governance address.
    function testManagementFee() public {
        // Increase vault's total supply
        deal(address(vault), address(0), 1e18, true);

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
        vm.prank(governance);
        vault.setManagementFee(200);

        // call to balanceOfAsset in harvest() will return 1e18
        vm.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfAsset.selector), abi.encode(1e18));
        // block.timestamp must be >= lastHarvest + LOCK_INTERVAL when harvesting
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        // Call harvest to update lastHarvest, note that no shares are minted here because
        // (block.timestamp - lastHarvest) = LOCK_INTERVAL + 1 =  3 hours + 1 second
        // and feeBps gets truncated to zero
        strategy.beginEpoch();
        strategy.endEpoch();

        vm.warp(block.timestamp + 365 days / 2);

        // Call harvest to trigger fee assessment
        strategy.beginEpoch();
        strategy.endEpoch();

        // Check that fees were assesed in the correct amounts => Management fees are sent to governance address
        // 1/2 of 2% of the vault's supply should be minted to governance
        assertEq(vault.balanceOf(governance), (100 * 1e18) / 10_000);
    }

    /// @notice Test profit is locked over the `LOCK_INTERVAL` period.
    function testLockedProfit() public {
        // call to balanceOfAsset in harvest() will return 1e18
        // block.timestamp must be >= lastHarvest + LOCK_INTERVAL when harvesting
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        BaseStrategy myStrat = strategy;
        asset.mint(address(myStrat), 1e18);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(address(strategy));
        vault.endEpoch();

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

        // Give the strat some assets
        asset.mint(address(vault), 999);

        // Harvest a gain of 1
        BaseStrategy myStrat = strategy;
        asset.mint(address(myStrat), 1);
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
        vm.prank(address(strategy));
        vault.endEpoch();

        assertEq(vault.totalAssets(), 999);
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);
        assertEq(vault.totalAssets(), 1000);
    }

    /// @notice Test that withdrawal fee is deducted while withdwaring.
    function testWithdrawalFee() public {
        vm.prank(governance);
        vault.setWithdrawalFee(50);

        uint256 amountAsset = 1e18;

        vm.startPrank(alice);
        asset.mint(alice, amountAsset);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amountAsset, alice);

        vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();
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
        asset.mint(address(this), 1e18);
        asset.approve(address(vault), 1e18);
        vault.deposit(1e18, address(this));

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
        assertEq(price.num, 10 ** uint256(asset.decimals()));

        asset.mint(address(vault), 2e18);

        // initial price is $100, but if we increase tvl the price increases
        Vault.Number memory price2 = vault.detailedPrice();
        assertTrue(price2.num > price.num);
    }

    function testCanUpgradeWithStrategySwap() public {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (governance, address(asset), "Affine High Yield LP - USDC-wETH", "affineSushiUsdcWeth")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        StrategyVault sVault = StrategyVault(address(proxy));

        //add a dummy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        MockEpochStrategy strategy1 = new MockEpochStrategy(sVault, strategists);
        MockEpochStrategy strategy2 = new MockEpochStrategy(sVault, strategists);

        vm.startPrank(governance);
        sVault.setStrategy(strategy1);

        // provide alice some assets
        uint256 initialAssets = 1e10;
        deal(address(sVault.asset()), alice, initialAssets);
        changePrank(alice);
        MockERC20(sVault.asset()).approve(address(sVault), initialAssets);
        sVault.deposit(initialAssets, alice);

        uint256 totalShares = sVault.totalSupply();
        // check tvl of vault and strategy 1

        assertEq(sVault.vaultTVL(), strategy1.totalLockedValue());
        StrategyVault impl2 = new StrategyVault();

        changePrank(governance);
        sVault.pause();

        sVault.upgradeTo(address(impl2));

        sVault.withdrawFromStrategy(strategy1.totalLockedValue());

        // check for strategy tvl to zero
        assertEq(strategy1.totalLockedValue(), 0);
        assertEq(sVault.vaultTVL(), initialAssets);

        sVault.setStrategy(strategy2);

        sVault.depositIntoStrategy(sVault.vaultTVL());

        // check tvl

        assertEq(sVault.vaultTVL(), strategy2.totalLockedValue());
        assertEq(totalShares, sVault.totalSupply());
        assertEq(strategy2.totalLockedValue(), initialAssets);
    }

    function testFailDepositWithoutStrategy() public {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (governance, address(asset), "Affine High Yield LP - USDC-wETH", "affineSushiUsdcWeth")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        StrategyVault sVault = StrategyVault(address(proxy));

        uint256 initialAssets = 1000 * 10 ** asset.decimals();
        deal(address(sVault.asset()), alice, initialAssets);
        vm.startPrank(alice);

        MockERC20(sVault.asset()).approve(address(sVault), initialAssets);

        sVault.deposit(initialAssets, alice);
    }

    function testFailWithdrawWithEscrowTransfer() public {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (governance, address(asset), "Affine High Yield LP - USDC-wETH", "affineSushiUsdcWeth")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        StrategyVault sVault = StrategyVault(address(proxy));

        //add a dummy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        MockEpochStrategy strategy1 = new MockEpochStrategy(sVault, strategists);

        vm.startPrank(governance);
        sVault.setStrategy(strategy1);

        uint256 initialAssets = 100_000 * (10 ** asset.decimals());
        sVault.setTvlCap(10 * initialAssets);

        console.log("initial assets %s deci %s", initialAssets, asset.decimals());
        console.log("Debt escrow %s", address(sVault.debtEscrow()));

        deal(address(asset), alice, initialAssets);

        changePrank(alice);

        MockERC20(sVault.asset()).approve(address(sVault), initialAssets);

        sVault.deposit(initialAssets, alice);

        sVault.transfer(address(sVault.debtEscrow()), 10 ** (sVault.decimals()));

        changePrank(strategists[0]);

        strategy1.endEpoch();
    }

    function testFailWithdrawWithNullEscrow() public {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (governance, address(asset), "Affine High Yield LP - USDC-wETH", "affineSushiUsdcWeth")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        StrategyVault sVault = StrategyVault(address(proxy));

        //add a dummy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        MockEpochStrategy strategy1 = new MockEpochStrategy(sVault, strategists);

        vm.startPrank(governance);
        sVault.setStrategy(strategy1);

        uint256 initialAssets = 100_000 * (10 ** asset.decimals());
        sVault.setTvlCap(10 * initialAssets);

        console.log("initial assets %s deci %s", initialAssets, asset.decimals());
        console.log("Debt escrow %s", address(sVault.debtEscrow()));

        deal(address(asset), alice, initialAssets);

        changePrank(alice);

        MockERC20(sVault.asset()).approve(address(sVault), initialAssets);

        sVault.deposit(initialAssets, alice);

        changePrank(strategists[0]);

        strategy1.beginEpoch();

        changePrank(alice);

        sVault.withdraw(initialAssets / 10, alice, alice);

        changePrank(strategists[0]);

        strategy1.endEpoch();
    }
}

contract SVaultUpgradeLiveTest is SVaultTest {
    function forkNet() public override {
        // fork polygon to test live vault
        /// @dev used fixed block for faster test and caching
        vm.createSelectFork("polygon", 44_212_000);
    }

    function testVaultAndStrategyUpgradeWithDeployedVault() public {
        // deployed vault
        StrategyVault mainnetVault = StrategyVault(0x684D1dbd30c67Fe7fF6D502A04e0E7076b4b9D46);

        // new vault to upgrade
        StrategyVault newVault = new StrategyVault();

        // prank gov
        vm.startPrank(0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0); // gov

        // vault old strategy
        MockEpochStrategy vaultStrategy = MockEpochStrategy(address(mainnetVault.strategy()));
        uint256 tvl = vaultStrategy.totalLockedValue();
        // check vault tvl
        assertEq(mainnetVault.vaultTVL(), tvl);

        // pause vault to strategy upgrade
        mainnetVault.pause();
        // upgrade vault
        mainnetVault.upgradeTo(address(newVault));

        // withdraw assets
        mainnetVault.withdrawFromStrategy(vaultStrategy.totalLockedValue());

        // check vault tvl should remain same, strategy tvl should be zero
        assertEq(mainnetVault.vaultTVL(), tvl);
        assertEq(vaultStrategy.totalLockedValue(), 0);

        //add a dummy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = address(this);

        MockEpochStrategy newStrategy = new MockEpochStrategy(mainnetVault, strategists);
        // replace with new strategy
        mainnetVault.setStrategy(newStrategy);
        // redeposit into strategy
        mainnetVault.depositIntoStrategy(mainnetVault.vaultTVL());

        // check vault tvl
        assertEq(mainnetVault.vaultTVL(), tvl);

        // check new strategy tvl
        assertEq(newStrategy.totalLockedValue(), tvl);
        console.log("vault tvl %s", tvl);
    }
}
