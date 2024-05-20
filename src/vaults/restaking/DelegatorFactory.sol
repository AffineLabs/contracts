// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";

interface IDelegatorFactory {
    function createDelegator(address _operator) external returns (address);
    function vault() external returns (address);
}

contract DelegatorFactory {
    address public vault;

    modifier onlyVault() {
        require(msg.sender == vault, "DF: only vault");
        _;
    }

    constructor(address _vault) {
        vault = _vault;
    }

    function createDelegator(address _operator) external onlyVault returns (address) {
        BeaconProxy bProxy = new BeaconProxy(
            UltraLRT(vault).beacon(), abi.encodeWithSelector(AffineDelegator.initialize.selector, vault, _operator)
        );
        return address(bProxy);
    }
}
