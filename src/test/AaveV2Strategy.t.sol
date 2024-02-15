// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {BridgeEscrow} from "src/vaults/cross-chain-vault/escrow/BridgeEscrow.sol";
import {AaveV2Strategy, ILendingPool} from "src/strategies/audited/AaveV2Strategy.sol";

/// @notice Test AAVE strategy
contract AAVEStratTest is TestPlus {
    using stdStorage for StdStorage;

    AffineVault vault;
    AaveV2Strategy strategy;
    ERC20 usdc;

    function _usdc() internal virtual returns (address) {
        return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    }

    function _lendingPool() internal virtual returns (address) {
        return 0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf;
    }

    function _fork() internal virtual {
        forkPolygon();
    }

    function _deployStrategy() internal virtual returns (address strat) {
        strat = address(new AaveV2Strategy(vault, ILendingPool(_lendingPool())));
    }

    function setUp() public {
        _fork();
        vault = AffineVault(address(Deploy.deployL2Vault()));
        usdc = ERC20(_usdc());
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(_usdc())));
        vm.store(address(vault), bytes32(slot), tokenAddr);

        strategy = AaveV2Strategy(_deployStrategy());

        vm.prank(governance);
        vault.addStrategy(strategy, 5000);
    }

    function _depositIntoStrat(uint256 assets) internal {
        // This testnet usdc has a totalSupply of  the max uint256, so we set `adjust` to false
        deal(address(usdc), address(this), assets, false);
        usdc.approve(address(strategy), type(uint256).max);

        // NOTE: deal does not work with aTokens, so we need to deposit into the lending pool to get aTokens
        // See https://github.com/foundry-rs/forge-std/issues/140
        strategy.invest(assets);
    }

    /// @notice Test strategy makes money over time.
    function testStrategyMakesMoney() public {
        // Vault deposits half of its tvl into the strategy
        // Give us (this contract) 1 USDC. Deposit into vault.
        _depositIntoStrat(1e6);

        // Go 10 days into the future and make sure that the vault makes money
        vm.warp(block.timestamp + 10 days);

        uint256 profit = strategy.aToken().balanceOf(address(strategy)) - 1e6 / 2;
        assertGe(profit, 100);
    }

    /// @notice Test divesting a certain amount works.
    function testStrategyDivestsOnlyAmountNeeded() public {
        // If the strategy already already has money, we only withdraw amountRequested - current money

        // Give the strategy 1 usdc and 2 aToken
        deal(address(usdc), address(strategy), 1e6, false);
        _depositIntoStrat(2e6);

        // Divest $2
        vm.prank(address(vault));
        strategy.divest(2e6);

        // We only withdrew 2 - 1 == 1 aToken. We gave 1 usdc and 1 aToken to the vault
        assertEq(usdc.balanceOf(address(vault)), 2e6);
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertApproxEqAbs(strategy.aToken().balanceOf(address(strategy)), 1e6, 1); // some truncation can happend with aTokens
    }

    /// @notice Test attempting to divest an amount more than the TVL results in divestment of the TVL amount.
    // We can attempt to divest more than our balance of aTokens
    function testDivestMoreThanTVL() public {
        _depositIntoStrat(1e6);

        vm.prank(address(vault));
        strategy.divest(2e6);

        assertEq(vault.vaultTVL(), 1e6);
        assertEq(strategy.totalLockedValue(), 0);
    }

    /// @notice Test not selling lp token when there is enough assets to cover divestment.
    function testDivestLessThanFloat() public {
        // If we try to divest $1 when we already have $2, we don't make any a bad call to the lendingPool
        // A bad call would be something like lendinPool.withdraw(0)
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

    /// @notice Test TVL calculation.
    function testTVL() public {
        deal(address(usdc), address(strategy), 3e6, false);

        assertEq(strategy.totalLockedValue(), 3e6);

        vm.startPrank(address(strategy));
        strategy.lendingPool().deposit(address(usdc), 2e6, address(strategy), 0);

        assertEq(strategy.totalLockedValue(), 3e6);
    }
}

/// @notice Test AAVE strategy
contract L1AAVEStratTest is AAVEStratTest {
    function _fork() internal override {
        forkEth();
    }

    function _usdc() internal override returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _lendingPool() internal override returns (address) {
        return 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    }
}
