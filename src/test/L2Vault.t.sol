// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./test.sol";
import { IHevm } from "./IHevm.sol";
import { MockERC20 } from "./MockERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { Relayer } from "../polygon/Relayer.sol";
import { Strategy } from "../Strategy.sol";
import { Deploy } from "./Deploy.sol";

contract VaultTest is DSTest {
    L2Vault vault;
    MockERC20 token;
    Relayer relayer;

    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        vault = Deploy.deployL2Vault();
        token = MockERC20(address(vault.token()));
        relayer = Relayer(address(vault.relayer()));
    }

    event Deposit(address indexed owner, uint256 tokenAmount, uint256 shareAmount);
    event Withdraw(address indexed owner, uint256 tokenAmount, uint256 shareAmount);

    function testDepositRedeem(uint256 amountToken) public {
        address user = address(this);
        token.mint(user, amountToken);

        // user gives max approval to vault for token
        token.approve(address(vault), type(uint256).max);
        hevm.expectEmit(true, false, false, true);
        emit Deposit(address(this), amountToken, amountToken);
        vault.deposit(amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        uint256 numShares = vault.balanceOf(user);
        assertEq(numShares, amountToken);
        assertEq(token.balanceOf(address(user)), 0);

        hevm.expectEmit(true, false, false, true);
        emit Withdraw(address(this), amountToken, amountToken);
        vault.redeem(numShares);

        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testDepositRedeemGasLess() public {
        address user = address(this);
        token.mint(user, 1e18);
        token.approve(address(vault), type(uint256).max);

        // truster forwarder is zero address and is the one who calls deposit on the relayer
        // The trusted forwarder adds the original user as the last twenty bytes of calldata
        hevm.startPrank(relayer.trustedForwarder());
        bytes memory depositData = abi.encodeWithSelector(relayer.deposit.selector, 1e18);
        address(relayer).call(abi.encodePacked(depositData, user));
        assertEq(vault.balanceOf(user), 1e18);

        bytes memory withdrawData = abi.encodeWithSelector(relayer.redeem.selector, 1e18);
        address(relayer).call(abi.encodePacked(withdrawData, user));
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), 1e18);

        hevm.stopPrank();

        // TODO: check that a bad user B imitating forwarder will
        // end with a call to deposit gasless with (B, amountToken)

        // only the relayer can call deposit gasless
        hevm.expectRevert(bytes("Only relayer"));
        vault.depositGasLess(user, 1e18);
        hevm.expectRevert(bytes("Only relayer"));
        vault.redeemGasLess(user, 1e18);
    }

    function testDepositWithdraw(uint64 amountToken) public {
        // Using a uint64 since we multiply totalSupply by amountToken in sharesFromTokens
        // Using a uint64 makes sure the calculation will not overflow

        address user = address(this);
        token.mint(user, amountToken);
        token.approve(address(vault), type(uint256).max);

        hevm.expectEmit(true, false, false, true);
        emit Deposit(address(this), amountToken, amountToken);
        vault.deposit(amountToken);

        // If vault is empty, tokens are converted to shares at 1:1
        assertEq(vault.balanceOf(user), amountToken);
        assertEq(token.balanceOf(user), 0);

        hevm.expectEmit(true, false, false, true);
        emit Withdraw(address(this), amountToken, amountToken);
        vault.withdraw(amountToken);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), amountToken);
    }

    function testDepositWithdrawGasLess() public {
        address user = address(this);
        token.mint(user, 1e18);
        token.approve(address(vault), type(uint256).max);

        hevm.startPrank(relayer.trustedForwarder());
        bytes memory depositData = abi.encodeWithSelector(relayer.deposit.selector, 1e18);
        address(relayer).call(abi.encodePacked(depositData, user));
        assertEq(vault.balanceOf(user), 1e18);

        bytes memory withdrawData = abi.encodeWithSelector(relayer.withdraw.selector, 1e18);
        address(relayer).call(abi.encodePacked(withdrawData, user));
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), 1e18);

        hevm.stopPrank();

        // only the relayer can withdraw
        hevm.expectRevert(bytes("Only relayer"));
        vault.withdrawGasLess(user, 1e18);
    }

    function testManagementFee() public {
        // Add total supply => occupies ERC20Upgradeable which inherits from two contracts with storage,
        // One contract has one slots and the other has 50 slots. totalSupply is at slot three in ERC20Up, so
        // the slot would is number 50 + 1 + 3 = 54 (index 53)
        hevm.store(address(vault), bytes32(uint256(53)), bytes32(uint256(1e18)));

        assertEq(vault.totalSupply(), 1e18);

        // Add this contract as a strategy
        Strategy myStrat = Strategy(address(this));
        vault.addStrategy(myStrat);

        // call to balanceOfToken in harvest() will return 1e18
        hevm.mockCall(address(this), abi.encodeWithSelector(Strategy.balanceOfToken.selector), abi.encode(1e18));
        // block.timestap must be >= lastHarvest + lockInterval when harvesting
        hevm.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        // Call harvest to update lastHarvest, note that no shares are minted here because
        // (block.timestamp - lastHarvest) = lockInterval + 1 =  3 hours + 1 second
        // and feeBps gets truncated to zero
        Strategy[] memory strategyList = new Strategy[](1);
        strategyList[0] = Strategy(address(this));
        vault.harvest(strategyList);

        hevm.warp(block.timestamp + vault.SECS_PER_YEAR() / 2);

        // Call harvest to trigger fee assessment
        vault.harvest(strategyList);

        // Check that fees were assesed in the correct amounts => Management fees are sent to governance address
        // 1/2 of 2% of the vault's supply should be minted to governance
        assertEq(vault.balanceOf(address(this)), (100 * 1e18) / 10_000);
    }

    function testLockedProfit() public {
        // Add this contract as a strategy
        Strategy myStrat = Strategy(address(this));
        vault.addStrategy(myStrat);

        // call to balanceOfToken in harvest() will return 1e18
        hevm.mockCall(address(this), abi.encodeWithSelector(Strategy.balanceOfToken.selector), abi.encode(1e18));
        // block.timestap must be >= lastHarvest + lockInterval when harvesting
        hevm.warp(vault.lastHarvest() + vault.lockInterval() + 1);

        token.mint(address(myStrat), 1e18);
        token.approve(address(vault), type(uint256).max);

        Strategy[] memory strategyList = new Strategy[](1);
        strategyList[0] = Strategy(address(this));
        vault.harvest(strategyList);

        assertEq(vault.lockedProfit(), 1e18);
        assertEq(vault.globalTVL(), 0);

        // Using up 50% of lockInterval unlocks 50% of profit
        hevm.warp(block.timestamp + vault.lockInterval() / 2);
        assertEq(vault.lockedProfit(), 1e18 / 2);
        assertEq(vault.globalTVL(), 1e18 / 2);
    }

    function testWithdrawlFee() public {
        uint256 amountToken = 1e18;
        vault.setWithdrawalFee(50);

        address user = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik
        hevm.startPrank(user);
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

        hevm.startPrank(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045);
        hevm.expectRevert(bytes("Only Governance."));
        vault.setManagementFee(300);
        hevm.expectRevert(bytes("Only Governance."));
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
    //     hevm.store(address(vault), bytes32(uint256(2)), bytes32(totalShares));
    //     emit log_named_uint("foo", vault.totalSupply());

    //     // update vaults total underlying tokens  => could just overwrite storage as well
    //     token.mint(address(vault), totalTokens);

    //     assertEq(vault.tokensFromShares(vault.sharesFromTokens(amountToken)), amountToken);
    // }
}
