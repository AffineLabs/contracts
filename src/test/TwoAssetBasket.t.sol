// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { TestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { Deploy } from "./Deploy.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { Dollar } from "../DollarMath.sol";
import { TwoAssetBasket } from "../polygon/TwoAssetBasket.sol";
import { Router } from "../polygon/Router.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { ERC4626RouterBase } from "../polygon/ERC4626RouterBase.sol";

contract BtcEthBasketTest is TestPlus {
    TwoAssetBasket basket;
    Router router;
    // NOTE: using mumbai addresses
    ERC20 usdc = ERC20(0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538);
    ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
    ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);

    function setUp() public {
        vm.createSelectFork("mumbai", 27549248);

        basket = Deploy.deployTwoAssetBasket(usdc);
        router = new Router("Alp", 0x52c8e413Ed9E961565D8D1de67e805E81b26C01b);
    }

    function mockUSDCPrice() internal {
        vm.mockCall(
            0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), uint256(1e8), 0, block.timestamp, uint80(1))
        );
    }

    function testDepositWithdraw() public {
        // mint some usdc, can remove hardcoded selector later
        uint256 mintAmount = 200 * 1e6;
        deal(address(usdc), address(this), mintAmount, true);
        usdc.approve(address(basket), type(uint256).max);
        basket.deposit(mintAmount, address(this));

        // you receive the dollar value of the amount of btc/eth deposited into the basket
        // the testnet usdc/btc usdc/eth pools do not have accurate prices
        assertTrue(basket.balanceOf(address(this)) > 0);
        uint256 vaultTVL = Dollar.unwrap(basket.valueOfVault());
        assertEq(basket.balanceOf(address(this)), (vaultTVL * 1e10) / 100);

        emit log_named_uint("VALUE OF VAULT", vaultTVL);
        emit log_named_uint("Initial AlpLarge price: ", basket.detailedPrice().num);

        uint256 inputReceived = basket.withdraw((mintAmount * 90) / 100, address(this), address(this));
        emit log_named_uint("DOLLARS WITHDRAWN: ", inputReceived);
    }

    function testRedeem() public {
        mockUSDCPrice();

        // give vault some btc/eth
        deal(address(btc), address(basket), 1e18);
        deal(address(weth), address(basket), 10e18);

        // Give us 50% of shares
        deal(address(basket), address(this), 1e18, true);
        deal(address(basket), alice, 1e18, true);

        // We sold approximately half of the assets in the vault
        uint256 oldTVL = Dollar.unwrap(basket.valueOfVault());
        uint256 assetsReceived = basket.redeem(1e18, address(this), address(this));
        assertTrue(assetsReceived > 0);
        assertApproxEqRel(Dollar.unwrap(basket.valueOfVault()), oldTVL / 2, 1e18 / 1);
    }

    function testMaxWithdraw() public {
        uint256 mintAmount = 100 * 1e6;
        deal(address(usdc), alice, mintAmount, true);
        deal(address(usdc), address(this), mintAmount, true);

        vm.startPrank(alice);
        usdc.approve(address(basket), type(uint256).max);
        basket.deposit(mintAmount, alice);
        vm.stopPrank();

        usdc.approve(address(basket), type(uint256).max);
        basket.deposit(mintAmount, address(this));

        emit log_named_uint("alices shares: ", basket.balanceOf(alice));
        emit log_named_uint("num shares: ", basket.balanceOf(address(this)));

        // Shares are $1 but have 18 decimals. Input asset only has  6 decimals
        // NOTE: The subtraction is not necessary when the USDC/USD price is set to 1
        basket.withdraw(basket.balanceOf(address(this)) / 1e12 - 1e6, address(this), address(this));
        emit log_named_uint("my shares: ", basket.balanceOf(address(this)));
        emit log_named_uint("valueOfVault: ", Dollar.unwrap(basket.valueOfVault()));
        emit log_named_uint("TotalSupplyOfVault: ", basket.totalSupply());
    }

    function testSlippageCheck() public {
        // The initial deposit gives as many shares as dollars deposited in the vault
        // If we expect 10 shares but only deposit 1 dollar, this will revert
        uint256 minShares = 10 * 10**18; // We're expecting that we 1 share, but
        deal(address(usdc), address(this), 1e6);
        usdc.approve(address(router), type(uint256).max);

        // basket.deposit will now return 0 shares as the number minted.
        // Mocking calls to basket does not work in `forge 0.2.0 (92427e7 2022-04-23T00:07:30.015620+00:00`
        // vm.mockCall(
        //     address(basket),
        //     abi.encodeWithSelector(basket.deposit.selector, 100, address(this)),
        //     abi.encode(1)
        // );

        // Since we can't mock the call to basket.deposit, router will actually have to call basket.deposit
        vm.prank(address(router));
        usdc.approve(address(basket), type(uint256).max);
        usdc.transfer(address(router), 1e6);
        vm.expectRevert(ERC4626RouterBase.MinSharesError.selector);
        router.deposit(IERC4626(address(basket)), address(this), 1e6, minShares);

        // TODO: add test for withdrawal check once this mocking works again
    }

    function testBuySplitsFuzz(uint256 balBtc, uint256 balEth) public {
        //	Let balances vary
        // 10k BTC is about 200M at todays prices, same for 133,000 ETH
        balBtc = bound(balBtc, 0, 10_000 * 1e18);
        balEth = bound(balEth, 0, 133e3 * 1e18);
        deal(address(btc), address(basket), balBtc);
        deal(address(weth), address(basket), balEth);

        // Test that if you are far from ideal amount, then we buy just one asset

        // Calculate idealAmount of Btc
        uint256 r1 = basket.ratios(0);
        uint256 r2 = basket.ratios(1);
        uint256 vaultDollars = Dollar.unwrap(basket.valueOfVault());
        uint256 idealBtcDollars = (r1 * (vaultDollars)) / (r1 + r2);
        uint256 idealEthDollars = vaultDollars - idealBtcDollars;

        (Dollar rawBtcDollars, Dollar rawEthDollars) = basket._valueOfVaultComponents();
        uint256 btcDollars = Dollar.unwrap(rawBtcDollars);
        uint256 ethDollars = Dollar.unwrap(rawEthDollars);

        uint256 amountInput = 100e6; // 100 USDC.
        (uint256 assetsToBtc, uint256 assetsToEth) = basket._getBuySplits(amountInput);
        uint256 inputDollars = amountInput * 1e2; // 100 usdc with 8 decimals
        if (btcDollars + inputDollars < idealBtcDollars) {
            // We buy just btc
            assertEq(assetsToBtc, amountInput);
            assertEq(assetsToEth, 0);
        } else if (ethDollars + inputDollars < idealEthDollars) {
            // We buy just eth
            assertEq(assetsToBtc, 0);
            assertEq(assetsToEth, amountInput);
        } else {
            // If you are close to ideal amount, then we buy some of both asset
            assertTrue(assetsToBtc > 0);
            assertTrue(assetsToEth > 0);
        }
    }

    function testBuySplits() public {
        // We have too much eth, so we only buy btc
        // Mocking balanceOf. Not using encodeCall because ERC20.balanceOf can't be found by solc
        vm.mockCall(address(basket.token2()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(100e18));

        uint256 amountInput = 100e6; // 100 USDC.
        (uint256 assetsToBtc, uint256 assetsToEth) = basket._getBuySplits(amountInput);

        assertEq(assetsToBtc, amountInput);
        assertEq(assetsToEth, 0);

        // We have too much btc so we only buy eth
        vm.clearMockedCalls();
        vm.mockCall(address(basket.token1()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(100e18));

        (assetsToBtc, assetsToEth) = basket._getBuySplits(amountInput);

        assertEq(assetsToBtc, 0);
        assertEq(assetsToEth, amountInput);

        // We have some of both, so we buy until we hit the ratios
        // The btc/eth ratio at the pinned block is ~0.08, so if we pick 0.1 we have roughly equal value
        vm.clearMockedCalls();
        vm.mockCall(address(basket.token1()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(1e18));
        vm.mockCall(address(basket.token2()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(10e18));

        // We have a split that is more even than 1:2
        uint256 largeInput = 100e6 * 1e6;
        (assetsToBtc, assetsToEth) = basket._getBuySplits(largeInput);
        assertTrue(assetsToBtc > largeInput / 3);
        assertTrue(assetsToEth > largeInput / 3);
    }

    function testSellSplits() public {
        // We have too much btc, so we only sell it
        // Mocking balanceOf. Not using encodeCall because ERC20.balanceOf can't be found by solc
        vm.mockCall(address(basket.token1()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(1e18));
        mockUSDCPrice();

        uint256 amountInput = 100e6; // 100 USDC.
        (Dollar rawDollarsFromBtc, Dollar rawDollarsFromEth) = basket._getSellSplits(amountInput);
        uint256 dollarsFromBtc = Dollar.unwrap(rawDollarsFromBtc);
        uint256 dollarsFromEth = Dollar.unwrap(rawDollarsFromEth);

        assertEq(dollarsFromBtc, amountInput * 1e2);
        assertEq(dollarsFromEth, 0);

        // We have too much eth so we only sell eth
        vm.clearMockedCalls();
        vm.mockCall(address(basket.token2()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(100e18));
        mockUSDCPrice();
        (rawDollarsFromBtc, rawDollarsFromEth) = basket._getSellSplits(amountInput);
        dollarsFromBtc = Dollar.unwrap(rawDollarsFromBtc);
        dollarsFromEth = Dollar.unwrap(rawDollarsFromEth);

        assertEq(dollarsFromBtc, 0);
        assertEq(dollarsFromEth, amountInput * 1e2);

        // // We have some of both, so we buy until we hit the ratios
        // See notes on how these values were chosen in testBuySplits
        vm.clearMockedCalls();
        vm.mockCall(address(basket.token1()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(1e18));
        vm.mockCall(address(basket.token2()), abi.encodeWithSelector(0x70a08231, address(basket)), abi.encode(10e18));
        mockUSDCPrice();

        // We have a split that is more even than 1:2
        uint256 largeInput = 100e6 * 1e6;
        (rawDollarsFromBtc, rawDollarsFromEth) = basket._getSellSplits(largeInput);
        dollarsFromBtc = Dollar.unwrap(rawDollarsFromBtc);
        dollarsFromEth = Dollar.unwrap(rawDollarsFromEth);
        assertTrue(dollarsFromBtc > (largeInput * 1e2) / 3);
        assertTrue(dollarsFromEth > (largeInput * 1e2) / 3);
    }

    function testVaultPause() public {
        vm.prank(governance);
        basket.pause();

        vm.expectRevert("Pausable: paused");
        basket.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        basket.withdraw(1e18, address(this), address(this));

        vm.prank(governance);
        basket.unpause();
        testDepositWithdraw();
    }

    function testDetailedPrice() public {
        // This function should work even if there is nothing in the vault
        TwoAssetBasket.Number memory price = basket.detailedPrice();
        assertEq(price.num, 100**8);

        address user = address(this);
        MockERC20(address(usdc)).mint(user, 2e6);
        usdc.approve(address(basket), type(uint256).max);

        basket.deposit(1e6, user);
        MockERC20(address(btc)).mint(address(basket), 1e18);
        TwoAssetBasket.Number memory price2 = basket.detailedPrice();
        assertGt(price2.num, 10**8);
    }

    function testAssetLimit() public {
        mockUSDCPrice();

        vm.prank(governance);
        basket.setAssetLimit(1000 * 1e8);

        deal(address(usdc), address(this), 2000e6, false);
        usdc.approve(address(basket), type(uint256).max);

        basket.deposit(500e6, address(this));
        assertEq(usdc.balanceOf(address(this)), 1500e6);

        // We only deposit 500 because the limit is 500 and 500 is already in the vault
        basket.deposit(1000e6, address(this));
        uint256 newUsdcBal = usdc.balanceOf(address(this));
        // We have to approximate since not exactly $500 dollars enters vault do to uniswap trade
        assertApproxEqRel(newUsdcBal, 1000e6, 1e18 / 2);

        uint256 shares = basket.deposit(200e6, address(this));
        assertEq(shares, 0);
        assertEq(usdc.balanceOf(address(this)), newUsdcBal);
    }

    function testTearDown() public {
        // Give alice and bob some shares
        deal(address(basket), alice, 1e18, true);
        deal(address(basket), bob, 1e18, true);

        // give the vault some bitcoin and ether
        deal(address(btc), address(basket), 1e18);
        deal(address(weth), address(basket), 10e18);

        // Call teardown and make sure they get money back
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        vm.startPrank(governance);
        basket.prepareForTeardown();
        assertTrue(basket.paused()); // We pause deposit/withdrawals before calling tearDown
        basket.tearDown(users);

        // alice and bob got usdc (they also get the same amount)
        assertTrue(usdc.balanceOf(alice) > 0);
        assertEq(usdc.balanceOf(alice), usdc.balanceOf(bob));

        // There's truncation since we round down, so we might have some dust left
        assertApproxEqAbs(usdc.balanceOf(address(basket)), 0, 10);

        // We dumped all btc and weth
        assertEq(btc.balanceOf(address(basket)), 0);
        assertEq(weth.balanceOf(address(basket)), 0);
    }
}
