// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { IWormhole } from "./IWormhole.sol";
import { IRootChainManager } from "./IRootChainManager.sol";

interface IStaging {
    function initialize(
        address vault,
        IWormhole wormhole,
        ERC20 token,
        IRootChainManager manager
    ) external;

    function l2Withdraw(uint256 amount) external;

    function l2ClearFund(uint256 amount) external;

    function l1ClearFund(uint256 amount, bytes calldata data) external;
}