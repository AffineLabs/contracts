// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDelegatorBeacon {
    function owner() external returns (address);
}

/**
 * @title DelegatorBeacon
 * @dev Delegator Beacon contract
 */
contract DelegatorBeacon is Ownable {
    UpgradeableBeacon immutable beacon;

    address public blueprint;

    /**
     * @dev Constructor
     * @param _initBlueprint Initial blueprint address
     * @param governance Governance address
     */
    constructor(address _initBlueprint, address governance) {
        beacon = new UpgradeableBeacon(_initBlueprint);
        blueprint = _initBlueprint;
        transferOwnership(governance);
    }
    /**
     * @notice Update the blueprint
     * @param _newBlueprint New blueprint address
     */

    function update(address _newBlueprint) public onlyOwner {
        beacon.upgradeTo(_newBlueprint);
        blueprint = _newBlueprint;
    }
    /**
     * @notice Get the implementation address
     * @return Implementation address
     */

    function implementation() public view returns (address) {
        return beacon.implementation();
    }
}
