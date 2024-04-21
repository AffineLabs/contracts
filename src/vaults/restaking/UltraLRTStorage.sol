// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {IStEth} from "src/interfaces/lido/IStEth.sol";

abstract contract UltraLRTStorage {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    // Token approval
    bytes32 public constant APPROVED_TOKEN = keccak256("APPROVED_TOKEN");

    uint256 public depositPaused;

    IStEth public constant STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    // TODO: Add LIDO interface

    modifier whenDepositNotPaused() {
        require(depositPaused == 1, "Deposit Paused.");
        _;
    }
}
