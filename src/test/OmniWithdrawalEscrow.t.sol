// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OmniWithdrawalEscrow} from "src/vaults/restaking/omni-lrt/OmniWithdrawalEscrow.sol";
import {OmniUltraLRT} from "src/vaults/restaking/omni-lrt/OmniUltraLRT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {console2} from "forge-std/console2.sol";

contract OmniWithdrawalEscrowTest is TestPlus {
    OmniWithdrawalEscrow escrow;
    OmniUltraLRT vault;
    MockERC20 asset;
    // setting up a symbiotic delegator to test out the escrow

    function _setupVault(address _asset) internal returns (OmniUltraLRT) {
        OmniUltraLRT impl = new OmniUltraLRT();

        bytes memory data = abi.encodeCall(
            OmniUltraLRT.initialize,
            ("TEST VAULT", "uLRT-TST", _asset, address(this), address(this), address(this), 0, 0, 0)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);

        return OmniUltraLRT(address(proxy));
    }

    function setUp() public {
        vault = new OmniUltraLRT();

        asset = new MockERC20("Mock", "MT", 18);
        // setup escrow
        vault = _setupVault(address(asset));
        escrow = new OmniWithdrawalEscrow(vault, address(asset));
    }

    function testRegisterDebt() public {
        uint256 amount = 10 ** vault.decimals();

        vm.prank(address(vault));
        escrow.registerWithdrawalRequest(alice, amount);

        assertEq(escrow.userDebtShare(0, alice), amount);

        (uint256 shares,,) = escrow.epochInfo(0);
        assertEq(shares, amount);

        // total debt
        assertEq(escrow.totalDebt(), amount);

        // register without vault
        vm.expectRevert();
        escrow.registerWithdrawalRequest(alice, amount);

        // withdrawableAssets

        assertEq(escrow.withdrawableAssets(alice, 0), 0);
        //withdrawableShares
        assertEq(escrow.withdrawableShares(alice, 0), 0);
    }

    function testEndEpoch() public {
        uint256 currentEpoch = escrow.currentEpoch();

        // test without vault
        vm.expectRevert();
        escrow.endEpoch();

        // test with vault debt share
        vm.prank(address(vault));
        escrow.endEpoch();
        assertEq(escrow.currentEpoch(), currentEpoch);

        testRegisterDebt();

        // debt share to resolve
        assertEq(escrow.getDebtToResolve(), 0);

        vm.prank(address(vault));
        escrow.endEpoch();

        assertEq(escrow.getDebtToResolve(), escrow.totalDebt());

        assertEq(escrow.currentEpoch(), currentEpoch + 1);
    }

    function testResolveDebtShares() public {
        // test without vault
        // test without debt
        uint256 assetAmount = 10 ** asset.decimals();
        uint256 shareAmount = 10 ** vault.decimals();

        vm.prank(address(vault));
        vm.expectRevert();
        escrow.resolveDebtShares(shareAmount, assetAmount);

        testEndEpoch();

        // test without vault
        vm.expectRevert();
        escrow.resolveDebtShares(0, 0);

        // resolve on more share
        vm.prank(address(vault));
        vm.expectRevert();
        escrow.resolveDebtShares(shareAmount + 100, assetAmount);

        // mint asset for vault

        asset.mint(address(vault), assetAmount);

        // approve asset to escrow
        vm.prank(address(vault));
        asset.approve(address(escrow), assetAmount);
        // resolve debt shares
        vm.prank(address(vault));
        escrow.resolveDebtShares(shareAmount, assetAmount);

        // check the state
        assertEq(escrow.getDebtToResolve(), 0);
        assertEq(escrow.resolvingEpoch(), 1);
    }

    function testRedeemAsset() public {
        // redeem before ending epoch
        vm.expectRevert();
        escrow.redeem(alice, 0);

        testResolveDebtShares();

        // redeem for invalid user
        vm.expectRevert();
        escrow.redeem(address(this), 0);

        // redeem for valid user
        escrow.redeem(alice, 0);

        // check the state
        assertEq(asset.balanceOf(address(alice)), 10 ** asset.decimals());

        assertEq(escrow.totalDebt(), 0);

        assertEq(escrow.resolvingEpoch(), 1);
    }

    function testRedeemShares() public {
        // redeem before share withdrawable
        deal(address(vault), address(escrow), 10 ** vault.decimals());

        vm.expectRevert();
        escrow.redeemShares(alice, 0);

        testRegisterDebt();
        // make share withdrawable
        vm.prank(address(vault));
        escrow.enableShareWithdrawal();

        // withdrawableShares
        // assertEq(escrow.withdrawableShares(alice, 0), 10 ** vault.decimals());

        escrow.redeemShares(alice, 0);

        // check the state
        assertEq(vault.balanceOf(address(alice)), 10 ** vault.decimals());

        // revert due to zero shares
        vm.expectRevert();
        escrow.redeemShares(alice, 0);

        assertEq(escrow.currentEpoch(), 0);
        assertEq(escrow.resolvingEpoch(), 0);
    }

    function testMultiRedeem() public {
        testResolveDebtShares();

        uint256[] memory epochs = new uint256[](1);

        epochs[0] = 0;

        uint256 assetAmount = escrow.getAssets(alice, epochs);
        assertEq(assetAmount, 10 ** asset.decimals());

        // redeem multiple epochs
        escrow.redeemMultiEpoch(alice, epochs);

        // check the state
        assertEq(asset.balanceOf(address(alice)), 10 ** asset.decimals());
    }

    function testSweep() public {
        testResolveDebtShares();

        vm.prank(address(vault));
        vm.expectRevert();
        escrow.sweep(address(asset));
        // sweep

        escrow.sweep(address(asset));

        // check the state
        assertEq(asset.balanceOf(address(this)), 10 ** asset.decimals());
    }
}
