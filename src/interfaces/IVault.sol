// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IStaging } from "./IStaging.sol";
import { IL1WormholeRouter, IL2WormholeRouter } from "./IWormholeRouter.sol";

interface IL1Vault {
    function wormholeRouter() external returns (IL1WormholeRouter);

    function staging() external returns(IStaging);

    function afterReceive() external;

    function processFundRequest(uint256 amountRequested) external;
}

interface IL2Vault {
    function wormholeRouter() external returns(IL2WormholeRouter);

    function staging() external returns(IStaging);

    function receiveTVL(uint256 tvl, bool received) external;

    function afterReceive(uint256 amount) external;
}