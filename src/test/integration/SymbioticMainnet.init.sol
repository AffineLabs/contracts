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

    function create(uint64 version, address owner_, bytes calldata data) external returns (address);
    function implementation(uint64) external view returns (address);
}

contract SymbioticMainnetTest is TestPlus {
    ISymVaultFactory factory = ISymVaultFactory(0x407A039D94948484D356eFB765b3c74382A050B4);
    address weth = 0x94373a4919B3240D86eA41593D5eBa789FEF3848; // wrapped staked eth

    address stEth = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034; //
    address wStETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;

    UltraLRT ultraWstEthS = UltraLRT(0x9666aB93452dC300C6b7412936D114bF1F737B1B);

    ISymVault symVault;

    SymbioticDelegatorV2 symDelegator;

    function _deploySymVault() internal returns (address) {
        ISymVault.InitParams memory params = ISymVault.InitParams({
            collateral: wStETH,
            burner: address(this),
            epochDuration: 1 days,
            depositWhitelist: false,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: address(this),
            depositWhitelistSetRoleHolder: address(this),
            depositorWhitelistRoleHolder: address(this),
            isDepositLimitSetRoleHolder: address(this),
            depositLimitSetRoleHolder: address(this)
        });

        return factory.create(1, address(this), abi.encode(params));
    }

    function setUp() public {
        vm.createSelectFork("holesky");
        symVault = ISymVault(_deploySymVault());
    }

    function testUpgradeOfDelegator() public {
        uint256 vaultTVL = ultraWstEthS.totalAssets();

        console2.log("vaultTVL %s", vaultTVL);

        SymbioticDelegator delegator = SymbioticDelegator(address(ultraWstEthS.delegatorQueue(0)));

        console2.log("delegator %s", delegator.totalLockedValue());
        console2.log("withddrawable assets", delegator.withdrawableAssets());

        uint256 delegatorAssets = delegator.totalLockedValue();

        vm.prank(ultraWstEthS.governance());
        ultraWstEthS.liquidationRequest(vaultTVL);

        vm.prank(ultraWstEthS.governance());
        ultraWstEthS.collectDelegatorDebt();

        console2.log("delegator %s", delegator.totalLockedValue());

        // drop delegator
        vm.prank(ultraWstEthS.governance());
        ultraWstEthS.dropDelegator(address(delegator));

        console2.log("delegator count %s", ultraWstEthS.delegatorCount());

        // upgrade delegator beacon
        DelegatorBeacon beacon = DelegatorBeacon(address(ultraWstEthS.beacon()));

        SymbioticDelegatorV2 newDelegatorImpl = new SymbioticDelegatorV2();

        vm.prank(ultraWstEthS.governance());
        beacon.update(address(newDelegatorImpl));

        // create new delegator
        vm.prank(ultraWstEthS.governance());
        ultraWstEthS.createDelegator(address(symVault));

        symDelegator = SymbioticDelegatorV2(address(ultraWstEthS.delegatorQueue(0)));

        console2.log("delegator count %s", ultraWstEthS.delegatorCount());

        console2.log("delegator %s", symDelegator.totalLockedValue());

        // now delegate to the new delegator
        uint256 totalAssets = ultraWstEthS.totalAssets();

        vm.prank(ultraWstEthS.governance());
        ultraWstEthS.delegateToDelegator(address(symDelegator), totalAssets);

        console2.log("delegator %s", symDelegator.totalLockedValue());

        console2.log("sym vault balance %s", symDelegator.totalLockedValue());
    }
}
