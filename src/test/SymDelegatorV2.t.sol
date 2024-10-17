// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "src/test/TestPlus.sol";
import {DefaultCollateral} from "src/test/mocks/SymCollateral.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

import {IVault as ISymVault} from "src/interfaces/symbiotic/IVault.sol";

import {console2} from "forge-std/console2.sol";
import {SymbioticDelegatorV2} from "src/vaults/restaking/SymDelegatorV2.sol";

interface ISymVaultFactory {
    struct InitParams {
        address collateral;
        address delegator;
        address slasher;
        address burner;
        uint48 epochDuration;
        bool depositWhitelist;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
    }

    function create(uint64 version, address owner_, bool withInitialize, bytes calldata data)
        external
        returns (address);
    function implementation(uint64) external view returns (address);
}

contract SymDelegatorV2Test is TestPlus {
    ISymVaultFactory factory = ISymVaultFactory(0x5035c15F3cb4364CF2cF35ca53E3d6FC45FC8899);
    address weth = 0x94373a4919B3240D86eA41593D5eBa789FEF3848; // wrapped staked eth

    address stEth = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034; //
    address wStETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;

    address delegator = 0x1c03fb03C560B775b70C71B0d5603091DED2c88c;

    address ultraWstEthS = 0x9666aB93452dC300C6b7412936D114bF1F737B1B;

    ISymVault symVault;

    SymbioticDelegatorV2 symDelegator;

    function _deploySymVault() internal returns (address) {
        ISymVaultFactory.InitParams memory params = ISymVaultFactory.InitParams({
            collateral: wStETH,
            delegator: address(delegator),
            slasher: address(0),
            burner: address(this),
            epochDuration: 1 days,
            depositWhitelist: false,
            defaultAdminRoleHolder: address(this),
            depositWhitelistSetRoleHolder: address(this),
            depositorWhitelistRoleHolder: address(this)
        });

        address vault = factory.create(1, address(this), true, abi.encode(params));
        return vault;
    }

    function setUp() public {
        vm.createSelectFork("holesky");
        console2.log("setUp %s", factory.implementation(1));
        symVault = ISymVault(_deploySymVault());

        console2.log("collateral %s", symVault.collateral());
        console2.log("asset ", UltraLRT(address(ultraWstEthS)).asset());

        symDelegator = new SymbioticDelegatorV2();
        symDelegator.initialize(address(ultraWstEthS), address(symVault));
    }

    function testDelegate() public {
        uint256 initialAsset = 1e18;
        deal(wStETH, address(this), initialAsset);

        ERC20(wStETH).approve(address(symDelegator), initialAsset);

        symDelegator.delegate(initialAsset);

        assertEq(symDelegator.totalLockedValue(), initialAsset);
    }

    function testWithdraw() public {
        testDelegate();

        vm.prank(address(ultraWstEthS));

        symDelegator.requestWithdrawal(1e18);

        assertEq(symDelegator.totalLockedValue(), 1e18);
        assertEq(symDelegator.queuedAssets(), 1e18);
        assertEq(symDelegator.withdrawableAssets(), 0);

        console2.log("epoch count %s", symDelegator.pendingEpochCount());
        console2.log("epoch index %s", symDelegator.pendingEpochIndex(1));
    }

    function testCompleteWithdrawal() public {
        testWithdraw();

        vm.expectRevert();
        symDelegator.completeWithdrawalRequest(1);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert();
        symDelegator.completeWithdrawalRequest(10);

        symDelegator.completeWithdrawalRequest(1);

        // rewithdrawal
        vm.expectRevert();
        symDelegator.completeWithdrawalRequest(1);

        assertEq(symDelegator.totalLockedValue(), 1e18);
        assertEq(symDelegator.queuedAssets(), 1e18);
        assertEq(symDelegator.withdrawableAssets(), 0);

        vm.expectRevert();
        symDelegator.addExternalEpoch(1);
    }

    function testExternalWithdrawal() public {
        testDelegate();

        vm.prank(address(symDelegator));
        symVault.withdraw(address(symDelegator), 1e18);

        assertEq(symDelegator.totalLockedValue(), 0);
        assertEq(symDelegator.queuedAssets(), 0);
        assertEq(symDelegator.withdrawableAssets(), 0);

        console2.log("epoch count %s", symDelegator.pendingEpochCount());

        // add epoch to the list
        // adding invalid epoch
        vm.expectRevert();
        symDelegator.addExternalEpoch(10);

        symDelegator.addExternalEpoch(1);

        // adding again
        vm.expectRevert();
        symDelegator.addExternalEpoch(1);

        console2.log("epoch count %s", symDelegator.pendingEpochCount());

        assertEq(symDelegator.pendingEpochCount(), 1);
        assertEq(symDelegator.pendingEpochIndex(1), 1);
        assertEq(symDelegator.totalLockedValue(), 1e18);
        assertEq(symDelegator.queuedAssets(), 1e18);
        assertEq(symDelegator.withdrawableAssets(), 0);
    }
}
