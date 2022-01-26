interface IL1Vault {
    function afterReceive() external;
}

interface IL2Vault {
    function afterReceive(uint256 amount) external;
}
