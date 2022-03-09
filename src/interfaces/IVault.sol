// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { WithdrawalQueue } from "../polygon/WithdrawalQueue.sol";

interface IL1Vault {
    function afterReceive() external;
}

interface IL2Vault {
    function withdrawalQueue() external returns (WithdrawalQueue);

    function afterReceive(bytes32 msgType, uint256 amount) external;
}