// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

interface IBaseBridge {
    function depositTransaction(
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes calldata _data
    ) external payable;
}