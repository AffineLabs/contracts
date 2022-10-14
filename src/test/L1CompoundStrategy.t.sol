// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

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
    address uniLikeSwapRouterAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address comptrollerAddr = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address cTokenAddr = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    L1Vault vault;
    L1CompoundStrategy strategy;

    // constants
    uint256 usdcBalancesStorageSlot = 0;
    uint256 oneUSDC = 1e6;
    uint256 halfUSDC = oneUSDC / 2;
    uint256 oneCOMP = 1e18;

    function setUp() public {
        vm.createSelectFork("ethereum", 14_971_385);
        vault = Deploy.deployL1Vault();

        // make vault token equal to the L1 usdc address
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1CompoundStrategy(
            vault,
            ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563), // cToken
            IComptroller(comptrollerAddr), // Comptroller
            IUniswapV2Router02(uniLikeSwapRouterAddr), // sushiswap router in eth mainnet
            ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888), // comp
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 // wrapped eth address
        );
    }

    function depositOneUSDCToVault() internal {
        // Give the Vault 1 usdc
        deal(address(usdc), address(vault), oneUSDC, true);
    }

    function investHalfOfVaultAssetInCompund() internal {
        changePrank(governance);
        vault.addStrategy(strategy, 5000);

        changePrank(address(vault.bridgeEscrow()));
        // After calling this, 5,000 bps of vault assets will be invested
        // in the aforementioed strategy and the remaining 5,000 bips will stay in vault
        // as a pile of idle USDC.
        vault.afterReceive();
    }

    function testTVL() public {
        deal(address(usdc), address(strategy), oneUSDC, true);
        assertEq(strategy.totalLockedValue(), oneUSDC);

        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        // We should have 1.5 USDC
        // Compound might round down when reporting balanceOfUnderlying
        // E.g. is you deposit .5 USDC (500_000) you might get (499_999) as a balanceOfUnderlying
        assertInRange(strategy.totalLockedValue(), oneUSDC + halfUSDC - 1, oneUSDC + halfUSDC + 1);
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

        // Simulate some accured COMP token.
        vm.mockCall(comptrollerAddr, abi.encodeWithSelector(IComptroller.compAccrued.selector), abi.encode(oneCOMP));
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
        assertEq(strategy.underlyingBalanceOfCToken(), 1e6);
    }

    function testCanSellRewards() public {
        // Give comp
        deal(address(strategy.comp()), address(strategy), 1e18);

        // If I divest then I have zero comp left
        vm.prank(address(vault));
        strategy.divest(100);

        assertEq(strategy.balanceOfComp(), 0);

        deal(address(strategy.comp()), address(strategy), 1e18);

        // Only the owner can call withdrawAssets
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.withdrawAssets(100, 0);

        strategy.withdrawAssets(100, 10e6);
    }
}
