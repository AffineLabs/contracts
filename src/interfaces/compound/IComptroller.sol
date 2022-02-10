// SPDX-License-Identifier:MIT
pragma solidity ^0.8.9;

interface IComptroller {
    function claimComp(address) external;

    function compAccrued(address) external view returns (uint256);

    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata) external returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
