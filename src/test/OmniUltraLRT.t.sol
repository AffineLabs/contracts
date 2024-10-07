// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OmniUltraLRT} from "src/vaults/restaking/omni-lrt/OmniUltraLRT.sol";
import {IPriceFeed} from "src/vaults/restaking/price-feed/IPriceFeed.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {OmniWithdrawalEscrow} from "src/vaults/restaking/omni-lrt/OmniWithdrawalEscrow.sol";
import {SymDelegatorFactory} from "src/vaults/restaking/SymDelegatorFactory.sol";

import {console2} from "forge-std/console2.sol";

contract TmpPriceFeed is IPriceFeed {
    function getPrice() external view returns (uint256, uint256) {
        return (1e8, block.timestamp);
    }
}

contract OmniUltraLRTTest is TestPlus {
    using Strings for uint256;

    OmniUltraLRT public vault;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address symbioticWbtcCollateral = 0x971e5b5D4baa5607863f3748FeBf287C7bf82618; // eth symbiotic collateral

    function setUp() public {
        // choose latest fork
        vm.createSelectFork("ethereum", 20_914_174); // has 4 eth limit in the symbiotic vault

        // deploy vault
        vault = OmniUltraLRT(_setupVault());

        _addWBTC();
    }

    function _setupWbtcUltraLRT() internal returns (address) {
        UltraLRT wbtcLRT = new UltraLRT();

        SymbioticDelegator delegatorImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), address(this));

        // initialize asset and governanace

        wbtcLRT.initialize(address(this), address(wbtc), address(beacon), "uBTC", "uBTC");

        WithdrawalEscrowV2 _escrow = new WithdrawalEscrowV2(wbtcLRT);

        wbtcLRT.setWithdrawalEscrow(_escrow);

        // set delegator factory
        SymDelegatorFactory dFactory = new SymDelegatorFactory(address(wbtcLRT));

        wbtcLRT.setDelegatorFactory(address(dFactory));

        // set delegator
        wbtcLRT.createDelegator(symbioticWbtcCollateral);

        return address(wbtcLRT);
    }

    function _addWBTC() internal {
        // add WBTC
        // setup omni withdrawal queue
        OmniWithdrawalEscrow escrow = new OmniWithdrawalEscrow(vault, wbtc);
        TmpPriceFeed priceFeed = new TmpPriceFeed();

        (uint256 _ps, uint256 _ts) = priceFeed.getPrice();
        console2.log("wbtc price %s %s", _ps, _ts);

        address wbtcVault = _setupWbtcUltraLRT();
        vault.addAsset(wbtc, wbtcVault, address(priceFeed), address(escrow));
    }

    function _setupVault() internal returns (address) {
        OmniUltraLRT vaultImpl = new OmniUltraLRT();

        // deploy proxy
        bytes memory initData = abi.encodeCall(
            OmniUltraLRT.initialize,
            ("OmniUltraLRT", "OULRT", wbtc, address(this), address(this), address(this), 0, 0, 0)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImpl), initData);

        return address(proxy);
    }

    function test() public {
        assertTrue(true); // test
    }

    function _getAsset(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }

    function testDeposit() public {
        uint256 amount = 1e8;
        // get wbtc
        _getAsset(wbtc, address(alice), amount);

        // approve
        vm.prank(alice);
        ERC20(wbtc).approve(address(vault), amount);

        // deposit
        vm.prank(alice);
        vault.deposit(wbtc, amount, alice);

        // check balance
        uint256 balance = ERC20(wbtc).balanceOf(address(vault));
        console2.log("balance %s", balance.toString());
        assertEq(balance, amount, "balance not match");

        // check user vault share
        uint256 share = vault.balanceOf(alice);
        console2.log("share %s", share);
        assertEq(share, (10 ** vault.decimals()), "share not match");
    }

    function testWithdraw() public {
        testDeposit();

        // test withdraw all
        uint256 shares = vault.balanceOf(alice);
        uint256 tokenAmount = vault.convertToAssets(shares);

        console2.log("shares %s, tokenAmount %s", shares, tokenAmount);

        // withdraw
        vm.prank(alice);
        vault.withdraw(tokenAmount, wbtc, alice);

        shares = vault.balanceOf(alice);
        tokenAmount = vault.convertToAssets(shares);

        console2.log("shares %s, tokenAmount %s", shares, tokenAmount);

        OmniWithdrawalEscrow tokenWQ = OmniWithdrawalEscrow(vault.wQueues(wbtc));

        uint256 balanceWq = vault.balanceOf(address(tokenWQ));

        console2.log("balance wq %s", balanceWq);

        // resolve debt share

        address[] memory tokens = new address[](1);
        tokens[0] = wbtc;

        // end epoch
        vault.endEpoch(tokens);

        // resolve debt

        vault.resolveDebt(tokens);

        // check balance
        uint256 wqTokenBalance = ERC20(wbtc).balanceOf(address(tokenWQ));

        console2.log("wq token balance %s", wqTokenBalance);

        // check user balance
        tokenWQ.redeem(alice, 0);

        uint256 userBalance = ERC20(wbtc).balanceOf(alice);
        console2.log("user balance %s", userBalance);

        assertEq(userBalance, 1e8, "user balance not match");
    }

    function _checkVaultTVL(uint256 amount) internal {
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, amount, "total assets not match");
    }

    function testWithdrawAfterInvest() public {
        uint256 initialAssets = 1e8;
        testDeposit();

        // invest
        address[] memory tokens = new address[](1);
        tokens[0] = wbtc;

        // amounts
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e8;

        vault.investAssets(tokens, amounts);

        // test total assets

        _checkVaultTVL(initialAssets);

        assertEq(ERC20(wbtc).balanceOf(address(vault)), 0, "vault balance not match");

        // deposit into sym btc vault

        assertEq(ERC20(wbtc).balanceOf(vault.vaults(wbtc)), initialAssets, "symbiotic vault balance not match");

        // invest into sym btc vault

        UltraLRT symWbtcVault = UltraLRT(vault.vaults(wbtc));

        address delegator = address(symWbtcVault.delegatorQueue(0));

        // delegate to delegator
        symWbtcVault.delegateToDelegator(address(delegator), initialAssets);

        // check vault tvl
        _checkVaultTVL(initialAssets);

        // withdraw
        vm.prank(alice);
        vault.withdraw(initialAssets, wbtc, alice);

        _checkVaultTVL(initialAssets);

        // end epochs

        vault.endEpoch(tokens);

        // divide assets

        vault.divestAssets(tokens, amounts);

        // check tvl
        _checkVaultTVL(initialAssets);

        // end epoch for symbiotic btc vault
        // this will also do liquidation request
        symWbtcVault.endEpoch();

        // resolve debt
        symWbtcVault.resolveDebt();

        // check tvl
        _checkVaultTVL(initialAssets);

        WithdrawalEscrowV2 wq = WithdrawalEscrowV2(symWbtcVault.escrow());

        // check wq balance

        uint256 wqBalance = ERC20(wbtc).balanceOf(address(wq));

        console2.log("wq balance %s", wqBalance);

        // resolve debt
        wq.redeem(address(vault), 0);

        // check tvl
        _checkVaultTVL(initialAssets);

        // resolve debt
        vault.resolveDebt(tokens);

        // reedem from omni withdrawal queue
        OmniWithdrawalEscrow tokenWQ = OmniWithdrawalEscrow(vault.wQueues(wbtc));

        tokenWQ.redeem(alice, 0);

        // check user balance
        uint256 userBalance = ERC20(wbtc).balanceOf(alice);

        console2.log("user balance %s", userBalance);

        assertEq(userBalance, initialAssets, "user balance not match");
        _checkVaultTVL(0);

        assertEq(vault.totalSupply(), 0);
    }
}
