// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {DefaultCollateral} from "src/test/mocks/SymCollateral.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

contract WithdrawalEscrowV2Test is TestPlus {
    WithdrawalEscrowV2 escrow;
    UltraLRT vault;
    MockERC20 asset;
    DefaultCollateral collateral;
    SymbioticDelegator delegator;
    uint256 initialAmount;

    function _pg() internal {
        vm.prank(governance);
    }
    // setting up a symbiotic delegator to test out the escrow

    function setUp() public {
        asset = new MockERC20("Mock", "MT", 18);

        collateral = new DefaultCollateral();
        collateral.initialize(address(asset), type(uint128).max, governance);

        vault = new UltraLRT();

        // easy to withdraw
        SymbioticDelegator delImpl = new SymbioticDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delImpl), governance);

        vault.initialize(governance, address(asset), address(beacon), "TEST VAULT", "uLRT-TST");

        delegator = new SymbioticDelegator();
        delegator.initialize(address(vault), address(collateral));

        initialAmount = 100 * (10 ** asset.decimals());
        // setup escrow
        escrow = new WithdrawalEscrowV2(vault);
        _pg();
        vault.setWithdrawalEscrow(escrow);
    }

    function testConstructor() public {
        WithdrawalEscrowV2 tmpEscrow = new WithdrawalEscrowV2(vault);
        assertEq(address(tmpEscrow.vault()), address(vault));
        assertEq(address(tmpEscrow.asset()), address(asset));
    }

    function testRegisterWithdrawRequest() public {
        // mint some tokens to this contract
        asset.mint(address(this), initialAmount);
        // approve vault to spend
        asset.approve(address(vault), initialAmount);
        // deposit to vault
        vault.deposit(initialAmount, address(this));
        // get the shares
        uint256 shares = vault.balanceOf(address(this));

        // manually transfer shares to escrow
        vault.transfer(address(escrow), shares);

        // register withdraw request except vault will fail
        vm.expectRevert();
        escrow.registerWithdrawalRequest(address(this), shares);
        // register withdraw request
        vm.prank(address(vault));
        escrow.registerWithdrawalRequest(address(this), shares);

        // check the state
        assertEq(escrow.userDebtShare(0, address(this)), shares);
        assertEq(escrow.totalDebt(), shares);
        (uint256 epochShares,) = escrow.epochInfo(0);
        assertEq(epochShares, uint128(shares));
    }

    function testEndEpoch() public {
        // check debt token shares
        assertEq(escrow.getDebtToResolve(), 0);
        // expect revert if no debt
        vm.prank(address(vault));
        vm.expectRevert("WEV2: No Debt.");
        escrow.endEpoch();

        // test Register Withdraw Request
        testRegisterWithdrawRequest();

        // check debt shares still zero as epoch not ended
        assertEq(escrow.getDebtToResolve(), 0);
        // check can withdraw
        assertFalse(escrow.canWithdraw(0));
        // end epoch without being called by vault
        vm.expectRevert("WE: must be vault");
        escrow.endEpoch();

        // end epoch
        vm.prank(address(vault));
        escrow.endEpoch();

        // check the state
        assertEq(escrow.getDebtToResolve(), escrow.totalDebt());
        assertEq(escrow.currentEpoch(), 1);
        assertEq(escrow.resolvingEpoch(), 0);
    }

    function testResolveDebtShares() public {
        // check resolve debt shares
        vm.expectRevert("WEV2: No debt.");
        vm.prank(address(vault));
        escrow.resolveDebtShares();
        // end epoch
        testEndEpoch();

        // resolve debt shares without being called by vault
        vm.expectRevert("WE: must be vault");
        escrow.resolveDebtShares();

        // resolve debt shares
        vm.prank(address(vault));
        escrow.resolveDebtShares();

        // check the state
        assertEq(escrow.getDebtToResolve(), 0);
        assertEq(escrow.totalDebt(), 0);
        (, uint256 assets) = escrow.epochInfo(0);
        assertEq(assets, initialAmount);
        // check can withdraw
        assertTrue(escrow.canWithdraw(0));
    }

    function testRedeem() public {
        // redeem before ending epoch
        vm.expectRevert("WE: epoch not resolved.");
        escrow.redeem(address(this), 0);
        // end epoch and resolve debt shares
        testResolveDebtShares();

        // redeem for invalid user with zero assets
        vm.expectRevert("WE: no assets to redeem");
        escrow.redeem(address(alice), 0);

        // redeem for valid user
        escrow.redeem(address(this), 0);

        // check the state
        assertEq(asset.balanceOf(address(this)), initialAmount);
        assertEq(escrow.totalDebt(), 0);
        assertEq(escrow.resolvingEpoch(), 1);
    }

    function testWithdrawableSharesAndAssets() public {
        // check withdrawable shares and assets
        assertEq(escrow.withdrawableShares(address(this), 0), 0);
        assertEq(escrow.withdrawableAssets(address(this), 0), 0);
        uint256 shares = vault.convertToShares(initialAmount);
        // end epoch and resolve debt shares
        testResolveDebtShares();

        // check withdrawable shares and assets
        assertEq(escrow.withdrawableShares(address(this), 0), shares);
        assertEq(escrow.withdrawableAssets(address(this), 0), initialAmount);

        // redeem
        escrow.redeem(address(this), 0);

        // check withdrawable shares and assets
        assertEq(escrow.withdrawableShares(address(this), 0), 0);
        assertEq(escrow.withdrawableAssets(address(this), 0), 0);
    }

    function testRedeemMultiEpoch() public {
        // end epoch and resolve debt shares
        testResolveDebtShares();

        // redeem multi epoch
        escrow.redeemMultiEpoch(address(this), new uint256[](1));

        // check the state
        assertEq(asset.balanceOf(address(this)), initialAmount);
        assertEq(escrow.totalDebt(), 0);
        assertEq(escrow.resolvingEpoch(), 1);
    }

    function testSweep() public {
        // end epoch and resolve debt shares
        testResolveDebtShares();

        // sweep not called by governance
        vm.expectRevert("WE: Must be gov");
        escrow.sweep(address(asset));

        // sweep
        _pg();
        escrow.sweep(address(asset));

        // check the state
        assertEq(asset.balanceOf(address(this)), 0);
        assertEq(escrow.totalDebt(), 0);
        assertEq(escrow.resolvingEpoch(), 1);
        assertEq(asset.balanceOf(address(governance)), initialAmount);
    }

    function testGetAssets() public {
        // end epoch and resolve debt shares
        assertEq(escrow.getAssets(address(this), new uint256[](1)), 0);
        testResolveDebtShares();

        // get assets
        assertEq(escrow.getAssets(address(this), new uint256[](1)), initialAmount);
    }
}
