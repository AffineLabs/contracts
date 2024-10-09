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

contract TmpPriceFeed2 is IPriceFeed {
    function getPrice() external view returns (uint256, uint256) {
        return (1e8 / 2, block.timestamp);
    }
}

contract OmniUltraLRTTest is TestPlus {
    using Strings for uint256;

    OmniUltraLRT public vault;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address symbioticWbtcCollateral = 0x971e5b5D4baa5607863f3748FeBf287C7bf82618; // eth symbiotic collateral

    address lbtc = 0x8236a87084f8B84306f72007F36F2618A5634494;
    address symLBTCCollateral = 0x9C0823D3A1172F9DdF672d438dec79c39a64f448;

    function setUp() public {
        // choose latest fork
        vm.createSelectFork("ethereum", 20_914_174); // has 4 eth limit in the symbiotic vault

        // deploy vault
        vault = OmniUltraLRT(_setupVault());

        _addWBTC();
        _addLBTC();
    }

    function _setupWbtcUltraLRT(address symAsset, address symCol) internal returns (address) {
        UltraLRT wbtcLRT = new UltraLRT();

        SymbioticDelegator delegatorImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), address(this));

        // initialize asset and governanace

        wbtcLRT.initialize(address(this), address(symAsset), address(beacon), "uBTC", "uBTC");

        WithdrawalEscrowV2 _escrow = new WithdrawalEscrowV2(wbtcLRT);

        wbtcLRT.setWithdrawalEscrow(_escrow);

        // set delegator factory
        SymDelegatorFactory dFactory = new SymDelegatorFactory(address(wbtcLRT));

        wbtcLRT.setDelegatorFactory(address(dFactory));

        // set delegator
        wbtcLRT.createDelegator(symCol);

        return address(wbtcLRT);
    }

    function _addWBTC() internal {
        // add WBTC
        // setup omni withdrawal queue
        OmniWithdrawalEscrow escrow = new OmniWithdrawalEscrow(vault, wbtc);
        TmpPriceFeed priceFeed = new TmpPriceFeed();

        (uint256 _ps, uint256 _ts) = priceFeed.getPrice();
        console2.log("wbtc price %s %s", _ps, _ts);

        address wbtcVault = _setupWbtcUltraLRT(wbtc, symbioticWbtcCollateral);
        vault.addAsset(wbtc, wbtcVault, address(priceFeed), address(escrow));
    }

    function _addLBTC() internal {
        // add LBTC
        // setup omni withdrawal queue
        OmniWithdrawalEscrow escrow = new OmniWithdrawalEscrow(vault, lbtc);
        TmpPriceFeed2 priceFeed = new TmpPriceFeed2(); // todo fix price feed

        (uint256 _ps, uint256 _ts) = priceFeed.getPrice();
        console2.log("lbtc price %s %s", _ps, _ts);

        address lbtcVault = _setupWbtcUltraLRT(lbtc, symLBTCCollateral);
        vault.addAsset(lbtc, lbtcVault, address(priceFeed), address(escrow));
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
        vault.endEpoch(tokens, true);

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

        _investNDelegateAssetToTokenVaultsDelegator(wbtc, initialAssets);

        // check vault tvl
        _checkVaultTVL(initialAssets);

        // withdraw
        vm.prank(alice);
        vault.withdraw(initialAssets, wbtc, alice);

        _checkVaultTVL(initialAssets);

        // end epochs
        vault.endEpoch(tokens, true);

        // check tvl
        _checkVaultTVL(initialAssets);

        // end epoch for symbiotic btc vault
        // this will also do liquidation request
        _divestNWithdrawFromTokenVault(wbtc, initialAssets, false);

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

    function _investNDelegateAssetToTokenVaultsDelegator(address token, uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // deposit into sym btc vault
        vault.investAssets(tokens, amounts);

        assertTrue(ERC20(token).balanceOf(vault.vaults(token)) >= amount, "token vault assets is not enough");

        // invest into sym btc vault

        UltraLRT symWbtcVault = UltraLRT(vault.vaults(token));

        address delegator = address(symWbtcVault.delegatorQueue(0));

        // delegate to delegator
        symWbtcVault.delegateToDelegator(address(delegator), amount);
    }

    function _divestNWithdrawFromTokenVault(address token, uint256 amount, bool requireManualDivest) internal {
        UltraLRT symWbtcVault = UltraLRT(vault.vaults(token));
        WithdrawalEscrowV2 wq = WithdrawalEscrowV2(symWbtcVault.escrow());

        // divide assets
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        if (requireManualDivest) {
            vault.divestAssets(tokens, amounts);
        }

        // end epoch for symbiotic btc vault
        // this will also do liquidation request
        uint256 resolvingEpoch = wq.resolvingEpoch();

        symWbtcVault.endEpoch();

        // resolve debt
        symWbtcVault.resolveDebt();

        // redeem
        wq.redeem(address(vault), resolvingEpoch);
    }

    function testPartialWithdrawal() public {
        uint256 initialAssets = 1e8;
        testDeposit();

        // invest
        address[] memory tokens = new address[](1);
        tokens[0] = wbtc;

        _investNDelegateAssetToTokenVaultsDelegator(wbtc, initialAssets);
        // check vault tvl
        _checkVaultTVL(initialAssets);

        // withdraw

        vm.prank(alice);
        vault.withdraw(initialAssets, wbtc, alice);

        _checkVaultTVL(initialAssets);

        // end epochs

        vault.endEpoch(tokens, false);

        _divestNWithdrawFromTokenVault(wbtc, initialAssets / 2, true);

        // check tvl
        _checkVaultTVL(initialAssets);

        uint256 prevDebtShares = vault.balanceOf(vault.wQueues(wbtc));

        // resolve debt
        vault.resolveDebt(tokens);

        // reedem from om

        _checkVaultTVL(initialAssets);

        // reedem from omni withdrawal queue
        OmniWithdrawalEscrow tokenWQ = OmniWithdrawalEscrow(vault.wQueues(wbtc));

        assertEq(vault.balanceOf(address(tokenWQ)), prevDebtShares, "wq balance not match");

        // divest remaining assets

        _divestNWithdrawFromTokenVault(wbtc, initialAssets / 2, true);

        // check tvl
        _checkVaultTVL(initialAssets);

        vault.resolveDebt(tokens);

        // reedem from omni withdrawal queue

        assertEq(vault.balanceOf(address(tokenWQ)), 0, "wq balance not match");

        // redeem
        tokenWQ.redeem(alice, 0);

        // check user balance
        uint256 userBalance = ERC20(wbtc).balanceOf(alice);
        assertEq(userBalance, initialAssets, "user balance not match");
    }

    function testDepositWithMultiAsset() public {
        uint256 lbtcAmount = 2e8;
        uint256 wbtcAmount = 1e8;

        testDeposit();
        // deposit lbtc

        _getAsset(lbtc, address(alice), lbtcAmount);

        // approve
        vm.prank(alice);
        ERC20(lbtc).approve(address(vault), lbtcAmount);

        // deposit
        vm.prank(alice);
        vault.deposit(lbtc, lbtcAmount, alice);

        console2.log("lbtc deposit success", vault.balanceOf(alice));
        console2.log("vault asset ", vault.totalAssets());

        assertEq(vault.totalAssets(), 2 * wbtcAmount, "total assets not match");
    }

    function testPartialWithdrawalQueueResolve() public {
        testDepositWithMultiAsset();

        // do withdrawal request for lbtc
        uint256 lbtcAmount = 2e8;

        // withdraw
        vm.prank(alice);
        vault.withdraw(lbtcAmount, lbtc, alice);

        _checkVaultTVL(2e8);

        // remove half of lbtc from vault
        vm.prank(address(vault));
        ERC20(lbtc).transfer(address(bob), lbtcAmount / 2);

        console2.log("lbtc transfer success", vault.totalAssets());

        address[] memory tokens = new address[](1);
        tokens[0] = lbtc;

        // end epochs
        vault.endEpoch(tokens, false);

        // resolve debt
        vault.resolveDebt(tokens);

        // omoni withdrawal queue
        OmniWithdrawalEscrow tokenWQ = OmniWithdrawalEscrow(vault.wQueues(lbtc));

        assertTrue(tokenWQ.shareWithdrawable(), "share withdrawal disabled");

        // withdrawable shares
        uint256 wqShares = tokenWQ.withdrawableShares(alice, 0);
        uint256 wqAssets = tokenWQ.withdrawableAssets(alice, 0);

        console2.log("shares %s, assets %s", wqShares, wqAssets);

        uint256 prevUserShare = vault.balanceOf(alice);
        // redeem assets
        tokenWQ.redeem(alice, 0);
        // redeem shares
        tokenWQ.redeemShares(alice, 0);

        assertEq(vault.balanceOf(alice), prevUserShare + wqShares, "user balance not match");
        assertEq(ERC20(lbtc).balanceOf(alice), wqAssets, "user balance not match");
    }
}
