// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {IVault as ISymVault} from "src/interfaces/symbiotic/IVault.sol";
import {ISymVaultFactory} from "src/interfaces/symbiotic/ISymVaultFactory.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";
import {SymbioticDelegatorV2} from "src/vaults/restaking/SymDelegatorV2.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

/* solhint-disable reason-string, no-console */

contract Deploy is Script {
    UltraLRT ultraWstEthS = UltraLRT(0x9666aB93452dC300C6b7412936D114bF1F737B1B);

    function _start() internal returns (address) {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("deployer %s", deployer);
        console2.log("Dep balance %s", deployer.balance);
        return deployer;
    }

    function _deploySymVault() internal returns (address) {
        address wStETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
        ISymVaultFactory factory = ISymVaultFactory(0x407A039D94948484D356eFB765b3c74382A050B4);

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

    function deleteOldDelegator() public {
        console2.log("SymHoleskyDeploy");
        _start();

        uint256 vaultTVL = ultraWstEthS.totalAssets();
        console2.log("vaultTVL %s", vaultTVL);

        SymbioticDelegator delegator = SymbioticDelegator(address(ultraWstEthS.delegatorQueue(0)));

        console2.log("delegator tvl: %s", delegator.totalLockedValue());

        // withdraw all from delegator
        ultraWstEthS.liquidationRequest(vaultTVL);

        // withdraw all from delegator
        ultraWstEthS.collectDelegatorDebt();

        console2.log("delegator tvl: %s", delegator.totalLockedValue());

        // drop the delegator
        ultraWstEthS.dropDelegator(address(delegator));

        console2.log("Delegator count %s", ultraWstEthS.delegatorCount());
    }

    function deployNewDelegator() public {
        console2.log("SymHoleskyDeploy");
        _start();

        ISymVault symVault = ISymVault(_deploySymVault());

        console2.log("collateral %s", symVault.collateral());
        console2.log("asset ", UltraLRT(address(0x9666aB93452dC300C6b7412936D114bF1F737B1B)).asset());

        SymbioticDelegatorV2 newDelegatorImpl = new SymbioticDelegatorV2();

        console2.log("Delegator impl  %s", address(newDelegatorImpl));
        DelegatorBeacon beacon = DelegatorBeacon(address(ultraWstEthS.beacon()));

        beacon.update(address(newDelegatorImpl));

        // create new delegator
        ultraWstEthS.createDelegator(address(symVault));

        console2.log("Delegator count %s", ultraWstEthS.delegatorCount());

        console2.log("Delegator address %s", address(ultraWstEthS.delegatorQueue(0)));
    }

    function delegateToNewDelegator() public {
        console2.log("SymHoleskyDeploy");
        _start();

        AffineDelegator symDelegator = AffineDelegator(address(ultraWstEthS.delegatorQueue(0)));

        console2.log("Delegator tvl %s", symDelegator.totalLockedValue());

        // delegate to delegator
        ultraWstEthS.delegateToDelegator(address(symDelegator), 10 * 1e18);

        console2.log("Delegator tvl %s", symDelegator.totalLockedValue());

        // request withdrawal
        ultraWstEthS.liquidationRequest(10 * 1e18);

        console2.log("Delegator tvl %s", symDelegator.totalLockedValue());
    }
}
