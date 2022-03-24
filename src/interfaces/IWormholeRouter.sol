// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IL1WormholeRouter {
    function reportTVL(uint256 tvl) external;

    function reportTrasferredFund(uint256 amount) external;

    function receiveFunds(bytes calldata message, bytes calldata data) external;
}

interface IL2WormholeRouter {
    function reportTrasferredFund(uint256 amount) external;

    function requestFunds(uint256 amount) external;

    function receiveFund(bytes calldata message) external;

    function receiveTVL(bytes calldata message) external;
}
