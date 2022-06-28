// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";

import { L1Vault } from "../ethereum/L1Vault.sol";
import { ICToken } from "../interfaces/compound/ICToken.sol";
import { IComptroller } from "../interfaces/compound/IComptroller.sol";
import { L1CompoundStrategy } from "../ethereum/L1CompoundStrategy.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";

// Contracts matching ^L1.*ForkMainnet$ pattern will run against
// Eth Mainnet fork.
contract L1CompoundStratTestForkMainnet is TestPlus {
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
        vault = Deploy.deployL1Vault();

        // make vault token equal to the L1 usdc address
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1CompoundStrategy(
            vault,
            ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563), // cToken
            IComptroller(comptrollerAddr), // Comptroller
            IUniLikeSwapRouter(uniLikeSwapRouterAddr), // sushiswap router in eth mainnet
            0xc00e94Cb662C3520282E6f5717214004A7f26888, // reward token -> comp token
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 // wrapped eth address
        );
    }

    function depositOneUSDCToVault() internal {
        // Give the Vault 1 usdc
        uint256 slot = stdstore.target(address(usdc)).sig(usdc.balanceOf.selector).with_key(address(vault)).find();
        vm.store(address(usdc), bytes32(slot), bytes32(uint256(oneUSDC)));
    }

    function investHalfOfVaultAssetInCompund() internal {
        vault.addStrategy(strategy, 5_000);
        // BridgeEscrow address is 0 in the default vault
        vm.prank(address(0));
        // This simulates an internal rebalance of vault assets among strategies of the 
        // vault. After calling this, 5,000 bips of vault assets will be invested
        // in the aforementioed strategy and the remaining 5,000 bips will stay in vault
        // as a pile of idle USDC.
        vault.afterReceive();
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
        vm.prank(address(vault));
        strategy.divest(tvl);
        assertInRange(usdc.balanceOf(address(vault)), oneUSDC - 1, oneUSDC);
    }
}
