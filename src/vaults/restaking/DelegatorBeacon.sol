// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DelegatorBeacon is Ownable {
    UpgradeableBeacon immutable beacon;

    address public blueprint;

    constructor(address _initBlueprint, address governance) {
        beacon = new UpgradeableBeacon(_initBlueprint);
        blueprint = _initBlueprint;
        transferOwnership(governance);
    }

    function update(address _newBlueprint) public onlyOwner {
        beacon.upgradeTo(_newBlueprint);
        blueprint = _newBlueprint;
    }

    function implementation() public view returns (address) {
        return beacon.implementation();
    }
}
