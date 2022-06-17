// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { IWormhole } from "./IWormhole.sol";
import { IRootChainManager } from "./IRootChainManager.sol";

interface IBridgeEscrow {
    function initializeL1(IRootChainManager manager) external;

    function initialize(
        address vault,
        IWormhole wormhole,
        ERC20 token
    ) external;
}
