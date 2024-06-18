// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {SymbioticDelegator} from "src/vaults/restaking/SymbioticDelegator.sol";

contract SymDelegatorFactory {
    address public vault;

    /**
     * @dev Modifier to allow function calls only from the vault
     */
    modifier onlyVault() {
        require(msg.sender == vault, "DF: only vault");
        _;
    }

    /**
     * @dev Constructor
     * @param _vault Vault address
     */
    constructor(address _vault) {
        vault = _vault;
    }

    /**
     * @notice Create a new delegator
     * @param _collateral Collateral address
     * @return Delegator address
     */
    function createDelegator(address _collateral) external onlyVault returns (address) {
        BeaconProxy bProxy = new BeaconProxy(
            UltraLRT(vault).beacon(), abi.encodeWithSelector(SymbioticDelegator.initialize.selector, vault, _collateral)
        );
        return address(bProxy);
    }
}
