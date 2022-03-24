// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IL1Vault {
    function staging() external returns(address);
    
    function afterReceive() external;

    function processFundRequest(uint256 amountRequested) external;
}

interface IL2Vault {
    function staging() external returns(address);
    
    function receiveTVL(uint256 tvl, bool received) external;

    function afterReceive(uint256 amount) external;
}
