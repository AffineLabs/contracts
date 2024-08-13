// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "src/interfaces/permit2/IPermit2.sol";
import {IAllowanceTransfer} from "src/interfaces/permit2/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "src/interfaces/permit2/ISignatureTransfer.sol";

import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {EigenDelegator} from "src/vaults/restaking/EigenDelegator.sol";

import {UltraLRT, Math} from "src/vaults/restaking/UltraLRT.sol";
import {UltraLRTRouter} from "src/vaults/restaking/UltraLRTRouter.sol";

import {IWETH} from "src/interfaces/IWETH.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {IWSTETH} from "src/interfaces/lido/IWSTETH.sol";

import {console2} from "forge-std/console2.sol";

contract TestUltraLRTRouter is TestPlus {
    uint256 privateKey1;
    address user1;

    uint256 privateKey2;
    address user2;

    IPermit2 permit2;

    UltraLRT vault;
    UltraLRT wStEthVault;

    UltraLRTRouter router;

    ERC20 asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStEth public stEth = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWSTETH public wStEth = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );
    uint256 initialAssets;

    bytes32 public PERMIT2_DOMAIN_SEPARATOR;

    function setUp() public {
        vm.createSelectFork("ethereum", 19_771_000);

        (user1, privateKey1) = makeAddrAndKey("user1");
        (user2, privateKey2) = makeAddrAndKey("user2");

        permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3); // permit 2 uniswap

        vault = new UltraLRT();
        // delegator implementation
        EigenDelegator delegatorImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delegatorImpl), governance);
        // initialization data
        vault.initialize(governance, address(asset), address(beacon), "uLRT", "uLRT");

        wStEthVault = new UltraLRT();
        wStEthVault.initialize(governance, address(wStEth), address(beacon), "uLRT", "uLRT");
        // define router

        router = new UltraLRTRouter();

        router.initialize(governance, address(weth), address(stEth), address(wStEth), address(permit2));

        initialAssets = 100 * (10 ** weth.decimals());

        PERMIT2_DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();
    }

    function getPermitTransferSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 privateKey,
        bytes32 domainSeparator,
        address spender
    ) internal pure returns (bytes memory sig) {
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, spender, permit.nonce, permit.deadline)
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function _getEth(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        return amount;
    }

    function _getStEth(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        stEth.submit{value: amount}(address(0));
        return stEth.balanceOf(to);
    }

    function _getWStEth(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        stEth.submit{value: amount}(address(0));

        uint256 stEthAmount = stEth.balanceOf(to);

        // approve
        vm.prank(to);
        stEth.approve(address(wStEth), stEthAmount);
        vm.prank(to);
        wStEth.wrap(stEthAmount);
        return wStEth.balanceOf(to);
    }

    function _getWEth(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        IWETH(address(weth)).deposit{value: amount}();
        return weth.balanceOf(to);
    }

    function testStEthToVault1Deposit() public {
        uint256 stEthAmount = _getStEth(user1, initialAssets);

        // approve permit2 with assets
        vm.prank(user1);
        stEth.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(asset), address(router));

        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(stEth), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositStEth(assetsToDeposit, address(vault), user1, nonce, block.timestamp + 100, signature);

        // check user balance
        assertApproxEqAbs(stEth.balanceOf(user1), stEthAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(vault.vaultAssets(), assetsToDeposit, 10);
        // check vault shares
        assertApproxEqAbs(vault.balanceOf(user1), assetsToDeposit, 10);
    }

    function testWStEthToVault1Deposit() public {
        uint256 beginAmount = _getWStEth(user1, initialAssets);
        ERC20 curAsset = ERC20(address(wStEth));
        // approve permit2 with assets

        // console2.log("B %s", vault.balanceOf(user1));

        vm.prank(user1);
        curAsset.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(curAsset), address(router));
        console2.log("==> %s", nonce);
        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositWStEth(assetsToDeposit, address(vault), user1, nonce, block.timestamp + 100, signature);

        uint256 depositedStEth = wStEth.getStETHByWstETH(assetsToDeposit);
        // check user balance
        assertApproxEqAbs(curAsset.balanceOf(user1), beginAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(vault.vaultAssets(), depositedStEth, 100);
        // // check vault shares
        assertApproxEqAbs(vault.balanceOf(user1), depositedStEth, 100);
        // console2.log("B %s", vault.balanceOf(user1));

        // get signature for approval of vault
        // get user nonce
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 100);
        (,, nonce) = permit2.allowance(user1, address(curAsset), address(router));

        nonce = nonce + 1;
        permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        signature = getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositWStEth(assetsToDeposit, address(vault), user1, nonce, block.timestamp + 100, signature);
    }

    function testWEthToVault1Deposit() public {
        uint256 beginAmount = _getWEth(user1, initialAssets);
        ERC20 curAsset = ERC20(address(weth));
        // approve permit2 with assets

        // console2.log("B %s", vault.balanceOf(user1));

        vm.prank(user1);
        curAsset.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(curAsset), address(router));

        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositWeth(assetsToDeposit, address(vault), user1, nonce, block.timestamp + 100, signature);

        uint256 depositedStEth = _getStEth(user1, assetsToDeposit);
        // console2.log("==> %s", depositedStEth);
        // console2.log("==> %s", vault.vaultAssets());
        // check user balance
        assertApproxEqAbs(curAsset.balanceOf(user1), beginAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(vault.vaultAssets(), depositedStEth, 100);
        // // check vault shares
        assertApproxEqAbs(vault.balanceOf(user1), depositedStEth, 100);
        // console2.log("B %s", vault.balanceOf(user1));
    }

    function testNativeToVault1Deposit() public {
        uint256 beginAmount = _getEth(user1, initialAssets);

        uint256 assetsToDeposit = 1e18;

        vm.prank(user1);
        vm.expectRevert(); // zero amount
        router.depositNative{value: 0}(address(vault), user1);

        vm.prank(user1);
        router.depositNative{value: assetsToDeposit}(address(vault), user1);
        // check user balance
        assertApproxEqAbs(user1.balance, beginAmount - assetsToDeposit, 10);

        uint256 depositedStEth = _getStEth(user1, assetsToDeposit);
        console2.log("==> %s", depositedStEth);
        console2.log("==> %s", vault.vaultAssets());

        // check vault assets
        assertApproxEqAbs(vault.vaultAssets(), depositedStEth, 10);
        // // check vault shares
        assertApproxEqAbs(vault.balanceOf(user1), depositedStEth, 10);
        // console2.log("B %s", vault.balanceOf(user1));
    }

    function testNativeToWStEthVaultDeposit() public {
        uint256 beginAmount = _getEth(user1, initialAssets);

        uint256 assetsToDeposit = 1e18;

        vm.prank(user1);
        router.depositNative{value: assetsToDeposit}(address(wStEthVault), user1);
        // check user balance
        assertApproxEqAbs(user1.balance, beginAmount - assetsToDeposit, 10);

        uint256 depositedStEth = _getWStEth(user1, assetsToDeposit);
        console2.log("==> %s", depositedStEth);
        console2.log("==> %s", wStEthVault.vaultAssets());

        // check vault assets
        assertApproxEqAbs(wStEthVault.vaultAssets(), depositedStEth, 10);
        // // check vault shares
        assertApproxEqAbs(wStEthVault.balanceOf(user1), depositedStEth, 10);
        // console2.log("B %s", vault.balanceOf(user1));
    }

    function testWEthToWStEthVaultDeposit() public {
        uint256 beginAmount = _getWEth(user1, initialAssets);
        ERC20 curAsset = ERC20(address(weth));
        // approve permit2 with assets

        // console2.log("B %s", vault.balanceOf(user1));

        vm.prank(user1);
        curAsset.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(curAsset), address(router));

        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositWeth(assetsToDeposit, address(wStEthVault), user1, nonce, block.timestamp + 100, signature);

        uint256 depositedWStEth = _getWStEth(user1, assetsToDeposit);
        // console2.log("==> %s", depositedStEth);
        // console2.log("==> %s", vault.vaultAssets());
        // check user balance
        assertApproxEqAbs(curAsset.balanceOf(user1), beginAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(wStEthVault.vaultAssets(), depositedWStEth, 100);
        // // check vault shares
        assertApproxEqAbs(wStEthVault.balanceOf(user1), depositedWStEth, 100);
        // console2.log("B %s", vault.balanceOf(user1));
    }

    function testWStEthToWStEthVaultDeposit() public {
        uint256 beginAmount = _getWStEth(user1, initialAssets);
        ERC20 curAsset = ERC20(address(wStEth));
        // approve permit2 with assets

        // console2.log("B %s", vault.balanceOf(user1));

        vm.prank(user1);
        curAsset.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(curAsset), address(router));

        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositWStEth(assetsToDeposit, address(wStEthVault), user1, nonce, block.timestamp + 100, signature);

        uint256 depositedWStEth = assetsToDeposit;
        // check user balance
        assertApproxEqAbs(curAsset.balanceOf(user1), beginAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(wStEthVault.vaultAssets(), depositedWStEth, 100);
        // // check vault shares
        assertApproxEqAbs(wStEthVault.balanceOf(user1), depositedWStEth, 100);
        // console2.log("B %s", vault.balanceOf(user1));
    }

    function testStEthToWStEthVaultDeposit() public {
        uint256 stEthAmount = _getStEth(user1, initialAssets);
        ERC20 curAsset = ERC20(address(stEth));
        // approve permit2 with assets
        vm.prank(user1);
        curAsset.approve(address(permit2), type(uint256).max);

        // get signature for approval of vault
        // get user nonce
        (,, uint48 nonce) = permit2.allowance(user1, address(curAsset), address(router));

        uint256 assetsToDeposit = 1e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(curAsset), amount: assetsToDeposit}),
            nonce: nonce,
            deadline: block.timestamp + 100
        });

        bytes memory signature =
            getPermitTransferSignature(permit, privateKey1, PERMIT2_DOMAIN_SEPARATOR, address(router));

        vm.prank(user1);
        router.depositStEth(assetsToDeposit, address(wStEthVault), user1, nonce, block.timestamp + 100, signature);

        uint256 depositedWStEth = wStEth.getWstETHByStETH(assetsToDeposit);
        // check user balance
        assertApproxEqAbs(curAsset.balanceOf(user1), stEthAmount - assetsToDeposit, 10);
        // check vault assets
        assertApproxEqAbs(wStEthVault.vaultAssets(), depositedWStEth, 10);
        // check vault shares
        assertApproxEqAbs(wStEthVault.balanceOf(user1), depositedWStEth, 10);
    }
}
