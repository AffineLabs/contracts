// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { IWormhole } from "./IWormhole.sol";
import { IRootChainManager } from "./IRootChainManager.sol";

interface IStaging {
    function initializeL1(IRootChainManager manager) external;

    function initialize(
        address vault,
        IWormhole wormhole,
        ERC20 token
    ) external;
}
