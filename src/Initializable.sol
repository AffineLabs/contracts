// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

abstract contract Initializable {
    bool private initialized;

    modifier initializer() {
        require(!initialized, "Contract instance has already been initialized");
        _;
        initialized = true;
    }

    modifier onlyIfInitialized() {
        require(initialized, "Contract instance needs to be initialized");
        _;
    }
}
