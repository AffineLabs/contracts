// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IL1WormholeRouter, IL2WormholeRouter } from "../interfaces/IWormholeRouter.sol";

interface IL1Vault {
    function wormholeRouter() external returns (IL1WormholeRouter);

    function staging() external returns(address);
    
    function afterReceive() external;

    function processFundRequest(uint256 amountRequested) external;
}

interface IL2Vault {
    function wormholeRouter() external returns(IL2WormholeRouter);

    function staging() external returns(address);
    
    function receiveTVL(uint256 tvl, bool received) external;

    function afterReceive(uint256 amount) external;
}
