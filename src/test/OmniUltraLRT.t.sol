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

    function testPauseNUnPause() public {
        // pause
        uint256 amount = 1e8;

        // get wbtc
        _getAsset(wbtc, address(alice), amount);

        // approve
        vm.prank(alice);
        ERC20(wbtc).approve(address(vault), amount);

        // pause vault
        vault.pause();
        // deposit
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(wbtc, amount, alice);

        // unpause
        vault.unpause();

        vm.prank(alice);
        vault.deposit(wbtc, amount, alice);
    }

    function testAddAssetNRemove() public {
        vm.expectRevert();
        vault.addAsset(wbtc, address(this), address(this), address(this));

        // adding max asset
        for (uint256 i = 2; i < 50; i++) {
            vault.addAsset(address(uint160(i)), address(this), address(this), address(this));
        }

        vm.expectRevert();
        vault.addAsset(address(uint160(50)), address(this), address(this), address(this));

        // remove zero address asset
        vm.expectRevert();
        vault.removeAsset(address(0));

        // remove asset
        vault.removeAsset(lbtc);

        testDeposit();

        vm.expectRevert();

        vault.removeAsset(wbtc);
    }

    function testDepositNWithdrawWithFailCondition() public {
        uint256 amount = 1e8;

        // get wbtc
        _getAsset(wbtc, address(alice), amount);
        // approve
        vm.prank(alice);
        ERC20(wbtc).approve(address(vault), amount);

        // deposit with zero address token
        vm.expectRevert();
        vault.deposit(address(0), amount, alice);

        // deposit with nonzero address invalid token
        vm.expectRevert();
        vault.deposit(address(uint160(50)), amount, alice);

        // deposit with zero amount
        vm.expectRevert();
        vault.deposit(wbtc, 0, alice);

        // deposit with zero receiver
        vm.expectRevert();
        vault.deposit(wbtc, amount, address(0));

        // deposit
        vm.prank(alice);
        vault.deposit(wbtc, amount, alice);

        // withdraw with zero address token
        vm.expectRevert();
        vault.withdraw(amount, address(0), alice);

        // withdraw with nonzero address invalid token
        vm.expectRevert();
        vault.withdraw(amount, address(uint160(50)), alice);

        // withdraw with zero amount
        vm.expectRevert();
        vault.withdraw(0, wbtc, alice);

        // withdraw with zero receiver
        vm.expectRevert();
        vault.withdraw(amount, wbtc, address(0));
    }

    function testInvestNDivestWithFailCases() public {
        uint256 amount = 1e8;

        // get wbtc
        _getAsset(wbtc, address(alice), amount);
        // approve
        vm.prank(alice);
        ERC20(wbtc).approve(address(vault), amount);

        // deposit
        vm.prank(alice);
        vault.deposit(wbtc, amount, alice);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory invalidAmounts = new uint256[](2);

        // invest with invalid length
        vm.expectRevert();
        vault.investAssets(tokens, invalidAmounts);

        // invest with zero address
        vm.expectRevert();
        vault.investAssets(tokens, amounts);

        // invest with invalid token
        tokens[0] = address(this);
        vm.expectRevert();
        vault.investAssets(tokens, amounts);

        // invest with zero amount
        tokens[0] = wbtc;
        vm.expectRevert();
        vault.investAssets(tokens, amounts);

        // invest with invalid balance
        amounts[0] = 2 * amount;
        vm.expectRevert();
        vault.investAssets(tokens, amounts);

        // invest
        amounts[0] = amount;
        vault.investAssets(tokens, amounts);

        // test divest
        // divest with invalid length
        vm.expectRevert();
        vault.divestAssets(tokens, invalidAmounts);

        // divest with zero address
        tokens[0] = address(0);
        vm.expectRevert();
        vault.divestAssets(tokens, amounts);

        // divest with invalid token
        tokens[0] = address(this);
        vm.expectRevert();
        vault.divestAssets(tokens, amounts);

        // // divest with zero amount
        tokens[0] = wbtc;
        amounts[0] = 0;
        vm.expectRevert();
        vault.divestAssets(tokens, amounts);

        // divest with invalid balance
        amounts[0] = 2 * amount;
        vm.expectRevert();
        vault.divestAssets(tokens, amounts);

        // divest
        amounts[0] = amount;
        vault.divestAssets(tokens, amounts);
    }

    function testSetFees() public {
        // set withdrawal fees
        uint256 feeBps = 10;

        // withdrawal fee
        vault.setWithdrawalFeeBps(feeBps);
        assertEq(vault.withdrawalFeeBps(), feeBps, "withdrawal fee not match");
        vm.expectRevert();
        vault.setWithdrawalFeeBps(10_001);

        // management fee
        vault.setManagementFeeBps(feeBps);
        assertEq(vault.managementFeeBps(), feeBps, "management fee not match");
        vm.expectRevert();
        vault.setManagementFeeBps(10_001);

        // performance fee
        vault.setPerformanceFeeBps(feeBps);
        assertEq(vault.performanceFeeBps(), feeBps, "performance fee not match");
        vm.expectRevert();
        vault.setPerformanceFeeBps(10_001);

        // set all fees at once
        feeBps = 100;
        vault.setFees(feeBps, feeBps + 1, feeBps + 2);
        assertEq(vault.performanceFeeBps(), feeBps, "performance fee not match");
        assertEq(vault.managementFeeBps(), feeBps + 1, "management fee not match");
        assertEq(vault.withdrawalFeeBps(), feeBps + 2, "withdrawal fee not match");
    }

    function testUpdateMinVaultWQ() public {
        assertEq(vault.minVaultWqEpoch(wbtc), 0, "min vault wq epoch not match");
        testPartialWithdrawal();
        address[] memory tokens = new address[](1);
        tokens[0] = wbtc;

        vault.updateMinVaultWqEpoch(tokens);

        assertEq(vault.minVaultWqEpoch(wbtc), 2, "min vault wq epoch not match");

        // check with zero tokens
        tokens[0] = address(0);
        vm.expectRevert();
        vault.updateMinVaultWqEpoch(tokens);

        // check with invalid token
        tokens[0] = address(this);
        vm.expectRevert();
        vault.updateMinVaultWqEpoch(tokens);
    }

    function testDisablePartialShareWithdrawal() public {
        // disable partial share withdrawal
        OmniWithdrawalEscrow tokenWQ = OmniWithdrawalEscrow(vault.wQueues(lbtc));
        assertEq(tokenWQ.shareWithdrawable(), false, "share withdrawal enabled");
        testPartialWithdrawalQueueResolve();
        assertEq(tokenWQ.shareWithdrawable(), true, "share withdrawal disabled");

        // disable share withdrawal
        address[] memory tokens = new address[](1);
        tokens[0] = lbtc;
        vault.disableShareWithdrawal(tokens);

        assertEq(tokenWQ.shareWithdrawable(), false, "share withdrawal enabled");

        // test with zero address
        tokens[0] = address(0);
        vm.expectRevert();
        vault.disableShareWithdrawal(tokens);

        // test with invalid token
        tokens[0] = address(this);
        vm.expectRevert();
        vault.disableShareWithdrawal(tokens);
    }

    function testSetPriceFeed() public {
        // set price feed

        uint256 amount = 1e8;

        testDepositWithMultiAsset();

        assertEq(vault.convertTokenToBaseAsset(lbtc, amount), amount / 2, "assets not match");
        assertEq(vault.convertTokenToBaseAsset(wbtc, amount), amount, "assets not match");
        assertEq(vault.convertBaseAssetToToken(lbtc, amount), amount * 2, "assets not match");

        // set new price feed

        TmpPriceFeed priceFeed = new TmpPriceFeed();

        vault.setPriceFeed(lbtc, address(priceFeed));

        assertEq(vault.totalAssets(), 3 * amount, "total assets not match");

        // test with fail cases

        // set zero token
        vm.expectRevert();
        vault.setPriceFeed(address(0), address(priceFeed));

        // set price feed with invalid token
        vm.expectRevert();
        vault.setPriceFeed(address(this), address(priceFeed));

        // set price feed with zero address
        vm.expectRevert();
        vault.setPriceFeed(lbtc, address(0));

        // test asset conversion

        assertEq(vault.convertTokenToBaseAsset(lbtc, amount), amount, "assets not match");
        assertEq(vault.convertTokenToBaseAsset(wbtc, amount), amount, "assets not match");
        assertEq(vault.convertBaseAssetToToken(lbtc, amount), amount, "assets not match");

        // set price feed with invalid token
        vm.expectRevert();
        vault.convertTokenToBaseAsset(address(this), amount);

        vm.expectRevert();
        vault.convertBaseAssetToToken(address(this), amount);
    }

    function testVaultShareAndAssetConversion() public {
        uint256 amount = 1e8;
        uint256 share = 10 ** vault.decimals();

        // when empty
        assertEq(vault.convertToAssets(share), amount, "assets not match");
        assertEq(vault.convertToShares(amount), share, "share not match");

        // test token tvl
        assertEq(vault.tokenTVL(wbtc), 0, "total assets not match");
        assertEq(vault.tokenTVL(lbtc), 0, "total assets not match");

        // do mutli asset deposit

        testDepositWithMultiAsset();

        // test token tvl
        assertEq(vault.tokenTVL(wbtc), amount, "total assets not match");
        assertEq(vault.tokenTVL(lbtc), amount, "total assets not match");

        assertEq(vault.convertToAssets(share), amount, "assets not match");
        assertEq(vault.convertToShares(amount), share, "share not match");

        // remove half of the assets from vault which is 1e8 wbtc
        vm.prank(address(vault));
        ERC20(wbtc).transfer(address(bob), amount);

        assertEq(vault.convertToAssets(share), amount / 2, "assets not match");
        assertEq(vault.convertToShares(amount), share * 2, "share not match");

        // check token tvl with zero address
        vm.expectRevert();
        vault.tokenTVL(address(0));
    }

    function testCanResolveWithdrawal() public {
        uint256 amount = 1e8;

        // when empty
        assertEq(vault.canResolveWithdrawal(amount, wbtc), false, "can resolve not match");

        vm.expectRevert();
        vault.canResolveWithdrawal(0, address(this));

        // do mutli asset deposit

        testDepositWithMultiAsset();

        // test token tvl
        assertEq(vault.canResolveWithdrawal(amount, wbtc), true, "can resolve not match");

        assertEq(vault.canResolveWithdrawal(amount + 1, wbtc), false, "can resolve not match");
    }

    function testPauseAndUnpauseAssets() public {
        // pause asset
        assertEq(vault.pausedAssets(wbtc), false, "asset paused");

        vm.expectRevert();
        vault.pauseAsset(address(0));

        vault.pauseAsset(wbtc);
        assertEq(vault.pausedAssets(wbtc), true, "asset not paused");

        uint256 amount = 1e8;
        // get wbtc
        _getAsset(wbtc, address(alice), amount);

        // approve
        vm.prank(alice);
        ERC20(wbtc).approve(address(vault), amount);

        // deposit will revert
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(wbtc, amount, alice);

        // unpause
        vm.expectRevert();
        vault.unpauseAsset(address(0));

        // unpause
        vault.unpauseAsset(wbtc);

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

        // pause asset to withdraw
        vault.pauseAsset(wbtc);

        // withdraw
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(amount, wbtc, alice);
    }
}
