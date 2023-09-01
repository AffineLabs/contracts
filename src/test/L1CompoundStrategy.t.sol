// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";
import {IComptroller} from "src/interfaces/compound/IComptroller.sol";
import {L1CompoundStrategy} from "src/strategies/L1CompoundStrategy.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @notice Test compound strategy
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
        forkEth();
        vault = Deploy.deployL1Vault();

        // make vault token equal to the L1 usdc address
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1CompoundStrategy(
            AffineVault(address(vault)),
            ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563) // cToken
        );

        // To be able to call functions restricted to strategist role.
        vm.startPrank(governance);
        strategy.grantRole(strategy.STRATEGIST(), address(this));
        vm.stopPrank();
    }

    function depositOneUSDCToVault() internal {
        // Give the Vault 1 usdc
        deal(address(usdc), address(vault), oneUSDC, true);
    }

    function _depositIntoStrat(uint256 assets) internal {
        // This testnet usdc has a totalSupply of  the max uint256, so we set `adjust` to false
        deal(address(usdc), address(this), assets, true);
        usdc.approve(address(strategy), type(uint256).max);

        // NOTE: deal does not work with aTokens, so we need to deposit into the lending pool to get aTokens
        // See https://github.com/foundry-rs/forge-std/issues/140
        strategy.invest(assets);
    }

    function investHalfOfVaultAssetInCompund() internal {
        vm.startPrank(governance);
        vault.addStrategy(strategy, 5000);

        vm.startPrank(address(vault.bridgeEscrow()));
        // After calling this, 5,000 bps of vault assets will be invested
        // in the aforementioed strategy and the remaining 5,000 bips will stay in vault
        // as a pile of idle USDC.
        vault.afterReceive();
        vm.stopPrank();
    }

    /// @notice Investing into strategy works.
    function testStrategyInvest() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        // Strategy deposits all of usdc into Compound
        assertInRange(strategy.totalLockedValue(), halfUSDC - 1, halfUSDC);
    }

    /// @notice Test strategy makes money with reward tokens.
    function testStrategyMakesMoneyWithCOMPToken() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        deal(address(strategy.COMP()), address(strategy), 2e18);
        strategy.claimRewards(0);
        assertGt(strategy.totalLockedValue(), halfUSDC);
    }

    /// @notice Test strategy makes money with lp tokens.
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

    /// @notice Test strategy looses money with lp tokens, when price goes down.
    function testStrategyLosesMoneyWithCToken() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        uint256 curretActualBalanceOfUnderlying = strategy.cToken().balanceOfUnderlying(address(strategy));
        // Simulate decrease in cUSDC price.
        vm.mockCall(
            cTokenAddr,
            abi.encodeWithSelector(ICToken.balanceOfUnderlying.selector),
            abi.encode(curretActualBalanceOfUnderlying / 2)
        );
        assertLt(strategy.totalLockedValue(), halfUSDC);
    }

    /// @notice Test divesting TVL amount from strategy works.
    function testDivestFromStrategy() public {
        depositOneUSDCToVault();
        investHalfOfVaultAssetInCompund();

        uint256 tvl = strategy.totalLockedValue();

        vm.startPrank(address(vault));
        strategy.divest(tvl);
        assertInRange(usdc.balanceOf(address(vault)), oneUSDC - 1, oneUSDC);
    }

    /// @notice Test divesting certain amount less than TVL from strategy works.
    function testStrategyDivestsOnlyAmountNeeded() public {
        // If the strategy already has money, we only withdraw amountRequested - current money

        deal(address(usdc), address(strategy), 3e6, false);

        // Mint two cTokens, only 1 should be liquidated during a request for $2
        vm.startPrank(address(strategy));
        strategy.cToken().mint(2e6);

        // Divest to get 2 usdc back to vault
        vm.startPrank(address(vault));
        strategy.divest(2e6);

        // We only withdrew 2 - 1 == 1 usdc worth of cToken. We gave 2 usdc to the vault
        assertEq(usdc.balanceOf(address(vault)), 2e6);
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertApproxEqAbs(strategy.cToken().balanceOfUnderlying(address(strategy)), 1e6, 1);
    }

    /// @notice Test attempting to divest an amount more than the TVL results in divestment of the TVL amount.
    // We can attempt to divest more than our balance of aTokens
    function testDivestMoreThanTVL() public {
        _depositIntoStrat(1e6);

        vm.prank(address(vault));
        strategy.divest(2e6);

        assertApproxEqAbs(vault.vaultTVL(), 1e6, 2);
        // There can still be a wei of cToken left unliquidated since balanceOfUnderlying rounds down
        assertApproxEqAbs(strategy.totalLockedValue(), 0, 1);
    }

    /// @notice Test not selling lp token when there is enough assets to cover divestment.
    function testDivestLessThanFloat() public {
        // If we try to divest $1 when we already have $2, we don't bother with the cToken and just
        // transfer from the usdc we have
        // Give the strategy 3 usdc
        deal(address(usdc), address(strategy), 3e6, false);

        vm.prank(address(vault));
        strategy.divest(2e6);

        assertEq(vault.vaultTVL(), 2e6);
        assertEq(strategy.totalLockedValue(), 1e6);
    }

    /// @notice Test investing a zero amount doesn't cause error.
    function testCanInvestZero() public {
        _depositIntoStrat(0);
    }

    /// @notice Test selling reward token works.
    function testCanSellRewards() public {
        deal(address(strategy.COMP()), address(strategy), 1e18);

        // Only the owner can call withdrawAssets
        vm.prank(alice);
        vm.expectRevert();
        strategy.claimRewards(100);

        strategy.claimRewards(100);
    }
}
