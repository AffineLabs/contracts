// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {ICToken} from "../interfaces/compound/ICToken.sol";
import {IComptroller} from "../interfaces/compound/IComptroller.sol";
import {L1CompoundStrategy} from "../ethereum/L1CompoundStrategy.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CompoundStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address cTokenAddr = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    L1Vault vault;
    L1CompoundStrategy strategy;

    // constants
    uint256 oneUSDC = 1e6;
    uint256 halfUSDC = oneUSDC / 2;

    function setUp() public {
        vm.createSelectFork("ethereum", 14_971_385);
        vault = Deploy.deployL1Vault();

        // make vault token equal to the L1 usdc address
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1CompoundStrategy(
            vault,
            ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563) // cToken
        );

        // To be able to call functions restricted to strategist role.
        vm.startPrank(vault.governance());
        vault.grantRole(vault.STRATEGIST(), address(this));
        vm.stopPrank();
    }

    function depositOneUSDCToVault() internal {
        // Give the Vault 1 usdc
        deal(address(usdc), address(vault), oneUSDC, true);
    }

    function investHalfOfVaultAssetInCompund() internal {
        vm.startPrank(governance);
        vault.addStrategy(strategy, 5000);

        changePrank(address(vault.bridgeEscrow()));
        // After calling this, 5,000 bps of vault assets will be invested
        // in the aforementioed strategy and the remaining 5,000 bips will stay in vault
        // as a pile of idle USDC.
        vault.afterReceive();
        vm.stopPrank();
    }

    function testStrategyInvest() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        // Strategy deposits all of usdc into Compound
        assertInRange(strategy.totalLockedValue(), halfUSDC - 1, halfUSDC);
    }

    function testStrategyMakesMoneyWithCOMPToken() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        deal(address(strategy.comp()), address(strategy), 2e18);
        strategy.claimRewards(0);
        assertGt(strategy.totalLockedValue(), halfUSDC);
    }

    function testStrategyMakesMoneyWithCToken() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        uint256 curretActualBalanceOfUnderlying = strategy.cToken().balanceOfUnderlying(address(strategy));
        // Simulate increase in cUSDC price.
        vm.mockCall(
            cTokenAddr,
            abi.encodeWithSelector(ICToken.balanceOfUnderlying.selector),
            abi.encode(curretActualBalanceOfUnderlying * 2)
        );
        assertGt(strategy.totalLockedValue(), halfUSDC);
    }

    function testStrategyLosesMoneyWithCToken() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        uint256 curretActualBalanceOfUnderlying = strategy.cToken().balanceOfUnderlying(address(strategy));
        // Simulate decrese in cUSDC price.
        vm.mockCall(
            cTokenAddr,
            abi.encodeWithSelector(ICToken.balanceOfUnderlying.selector),
            abi.encode(curretActualBalanceOfUnderlying / 2)
        );
        assertLt(strategy.totalLockedValue(), halfUSDC);
    }

    function testDivestFromStrategy() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        uint256 tvl = strategy.totalLockedValue();

        changePrank(address(vault));
        strategy.divest(tvl);
        assertInRange(usdc.balanceOf(address(vault)), oneUSDC - 1, oneUSDC);
    }

    function testStrategyDivestsOnlyAmountNeeded() public {
        // If the strategy already already has money, we only withdraw amountRequested - current money

        // Give the strategy 1 usdc and 2 usdc worth of cTokens
        deal(address(usdc), address(strategy), 3e6, false);

        vm.startPrank(address(strategy));
        strategy.cToken().mint(2e6);

        // Divest to get 2 usdc back to vault
        changePrank(address(vault));
        strategy.divest(2e6);

        // We only withdrew 2 - 1 == 1 usdc worth of cToken. We gave 2 usdc to the vault
        assertEq(usdc.balanceOf(address(vault)), 2e6);
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertEq(strategy.cToken().balanceOfUnderlying(address(strategy)), 1e6);
    }

    function testCanSellRewards() public {
        deal(address(strategy.comp()), address(strategy), 1e18);

        // Only the owner can call withdrawAssets
        vm.prank(alice);
        vm.expectRevert();
        strategy.claimRewards(100);

        strategy.claimRewards(100);
    }
}
