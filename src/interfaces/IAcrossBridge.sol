// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IAcrossBridge {
     function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        int64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes calldata message,
        uint256 maxCount
    ) external payable;

    function speedUpDeposit(
        address deoisitor,
        int64 updatedRelayerFeePct,
        uint32 depositId,
        address updatedRecipient,
        bytes calldata updatedMessage,
        bytes calldata depositorSignature
    ) external payable;

    function getCurrentTime() external view returns (uint256);

    function depositQuoteTimeBuffer() external view returns (uint32);
}