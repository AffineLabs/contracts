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
    ERC20 usdc = ERC20(0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538);
    ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
    ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);

    function setUp() public {
        // NOTE: using mumbai addresses
        vm.createSelectFork("mumbai", 27549248);

        basket = new TwoAssetBasket(
            address(this), // governance
            address(0), // forwarder
            10_000 * 1e6, // once the vault is $10,000 out of balance then we can rebalance
            5_000 * 1e6, // selling in $5,000 blocks
            IUniLikeSwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
            usdc, // mintable usdc
            // WBTC AND WETH
            [btc, weth],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [
                AggregatorV3Interface(0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0),
                AggregatorV3Interface(0x007A22900a3B98143368Bd5906f8E17e9867581b),
                AggregatorV3Interface(0x0715A7794a1dc8e42615F059dD6e406A6594651A)
            ]
        );
        router = new Router("Alp", 0x52c8e413Ed9E961565D8D1de67e805E81b26C01b);
    }

    function testDepositWithdraw() public {
        // mint some usdc, can remove hardcoded selector later
        uint256 mintAmount = 100 * 1e6;
        deal(address(usdc), address(this), mintAmount, true);
        usdc.approve(address(basket), type(uint256).max);
        basket.deposit(mintAmount, address(this));

        // you receive the dollar value of the amount of btc/eth deposited into the basket
        // the testnet usdc/btc usdc/eth pools do not have accurate prices
        assertTrue(basket.balanceOf(address(this)) > 0);
        uint256 vaultTVL = Dollar.unwrap(basket.valueOfVault());
        assertEq(basket.balanceOf(address(this)), vaultTVL * 1e10);
        emit log_named_uint("VALUE OF VAULT", vaultTVL);

        uint256 inputReceived = basket.withdraw((mintAmount * 90) / 100, address(this), address(this));
        emit log_named_uint("DOLLARS WITHDRAWN: ", inputReceived);
    }

    function testMaxWithdraw() public {
        address alice = mkaddr("alice");

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

    function testVaultPause() public {
        basket.pause();

        vm.expectRevert("Pausable: paused");
        basket.deposit(1e18, address(this));

        vm.expectRevert("Pausable: paused");
        basket.withdraw(1e18, address(this), address(this));

        basket.unpause();
        testDepositWithdraw();
    }

    function testAuction() public {}

    function testDetailedPrice() public {
        // This function should work even if there is nothing in the vault
        TwoAssetBasket.Number memory price = basket.detailedPrice();
        assertEq(price.num, 10**8);

        address user = address(this);
        MockERC20(address(usdc)).mint(user, 2e6);
        usdc.approve(address(basket), type(uint256).max);

        basket.deposit(1e6, user);
        MockERC20(address(btc)).mint(address(basket), 1e18);
        TwoAssetBasket.Number memory price2 = basket.detailedPrice();
        assertGt(price2.num, 10**8);
    }
}
