// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract OwnedInitializable is Initializable {
    address immutable deployer;

    constructor() {
        deployer = msg.sender;
    }

    modifier onlyDeployer() {
        require(msg.sender == deployer, "Initializable: init done");
        _;
    }
}
