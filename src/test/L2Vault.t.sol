// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./MockERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseStrategy } from "../BaseStrategy.sol";
import { Deploy } from "./Deploy.sol";

contract L2VaultTest is DSTestPlus {
    L2Vault vault;
    MockERC20 token;

    function setUp() public {
        vault = Deploy.deployL2Vault();
        token = MockERC20(address(vault.token()));
    }

    // Adding this since this test contract is used as a strategy
    function totalLockedValue() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    event Deposit(address indexed owner, uint256 tokenAmount, uint256 shareAmount);
    event Withdraw(address indexed owner, uint256 tokenAmount, uint256 shareAmount);

    function testDepositRedeem(uint256 amountToken) public {
        address user = address(this);
        token.mint(user, amountToken);

        // user gives max approval to vault for token
        token.approve(address(vault), type(uint256).max);
        cheats.expectEmit(true, false, false, true);
        emit Deposit(address(this), amountToken, amountToken);
        vault.deposit(amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);

        cheats.expectEmit(true, false, false, true);
        emit Withdraw(address(this), amountToken, amountToken);
        vault.redeem(numShares);

        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testDepositWithdraw(uint64 amountToken) public {
        // Using a uint64 since we multiply totalSupply by amountToken in sharesFromTokens
        // Using a uint64 makes sure the calculation will not overflow

        address user = address(this);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);

        cheats.expectEmit(true, false, false, true);
        emit Deposit(address(this), amountToken, amountToken);
        vault.deposit(amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        assertEq(vault.balanceOf(user), amountToken);
        assertEq(token.balanceOf(user), 0);

        cheats.expectEmit(true, false, false, true);
        emit Withdraw(address(this), amountToken, amountToken);
        vault.withdraw(amountToken);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testManagementFee() public {
        // Add total supply => occupies ERC20Upgradeable which inherits from two contracts with storage,
        // One contract has one slots and the other has 50 slots. totalSupply is at slot three in ERC20Up, so
        // the slot would is number 50 + 1 + 3 = 54 (index 53)
        cheats.store(address(vault), bytes32(uint256(53)), bytes32(uint256(1e18)));

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat);

        // call to balanceOfToken in harvest() will return 1e18
        cheats.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfToken.selector), abi.encode(1e18));
        // block.timestap must be >= lastHarvest + lockInterval when harvesting
        cheats.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        // Call harvest to update lastHarvest, note that no shares are minted here because
        // (block.timestamp - lastHarvest) = lockInterval + 1 =  3 hours + 1 second
        // and feeBps gets truncated to zero
        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        cheats.warp(block.timestamp + vault.SECS_PER_YEAR() / 2);

        // Call harvest to trigger fee assessment
        vault.harvest(strategyList);

        // Check that fees were assesed in the correct amounts => Management fees are sent to governance address
        // 1/2 of 2% of the vault's supply should be minted to governance
        assertEq(vault.balanceOf(address(this)), (100 * 1e18) / 10_000);
    }

    function testLockedProfit() public {
        // Add this contract as a strategy
        BaseStrategy myStrat = BaseStrategy(address(this));
        vault.addStrategy(myStrat);

        // call to balanceOfToken in harvest() will return 1e18
        cheats.mockCall(address(this), abi.encodeWithSelector(BaseStrategy.balanceOfToken.selector), abi.encode(1e18));
        // block.timestap must be >= lastHarvest + lockInterval when harvesting
        cheats.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        token.mint(address(myStrat), 1e18);
        token.approve(address(vault), type(uint256).max);

        BaseStrategy[] memory strategyList = new BaseStrategy[](1);
        strategyList[0] = BaseStrategy(address(this));
        vault.harvest(strategyList);

        assertEq(vault.lockedProfit(), 1e18);
        assertEq(vault.globalTVL(), 0);

        // Using up 50% of lockInterval unlocks 50% of profit
        cheats.warp(block.timestamp + vault.lockInterval() / 2);
        assertEq(vault.lockedProfit(), 1e18 / 2);
        assertEq(vault.globalTVL(), 1e18 / 2);
    }

    function testWithdrawlFee() public {
        uint256 amountToken = 1e18;
        vault.setWithdrawalFee(50);

        address user = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik
        cheats.startPrank(user);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amountToken);

        vault.redeem(vault.balanceOf(user));
        assertEq(vault.balanceOf(user), 0);

        // User gets the original amount with 50bps deducted
        assertEq(token.balanceOf(user), (amountToken * (10_000 - 50)) / 10_000);
        // Governance gets the 50bps fee
        assertEq(token.balanceOf(vault.governance()), (amountToken * 50) / 10_000);
    }

    function testSettingFees() public {
        vault.setManagementFee(300);
        assertEq(vault.managementFee(), 300);
        vault.setWithdrawalFee(10);
        assertEq(vault.withdrawalFee(), 10);

        cheats.startPrank(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045);
        cheats.expectRevert(bytes("Only Governance."));
        vault.setManagementFee(300);
        cheats.expectRevert(bytes("Only Governance."));
        vault.setWithdrawalFee(10);
    }
    // TODO: Get the below test to pass
    // function testShareTokenConversion(
    //     uint256 amountToken,
    //     uint256 totalShares,
    //     uint256 totalTokens
    // ) public {
    //     // update vaults total supply (number of shares)
    //     // storage slots can be found in dapptools' abi output
    //     cheats.store(address(vault), bytes32(uint256(2)), bytes32(totalShares));
    //     emit log_named_uint("foo", vault.totalSupply());

    //     // update vaults total underlying tokens  => could just overwrite storage as well
    //     token.mint(address(vault), totalTokens);

    //     assertEq(vault.tokensFromShares(vault.sharesFromTokens(amountToken)), amountToken);
    // }
}
