// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import { FxBaseChildTunnel } from '../tunnel/FxBaseChildTunnel.sol';
import { BytesLib } from '../lib/BytesLib';

/** 
 * @title FxStateChildTunnel
 */
contract FxStateChildTunnel is FxBaseChildTunnel {
    using BytesLib for bytes;
    mapping(address => uint256) private _balances;
    uint256 public latestStateId;
    address public latestRootMessageSender;
    bytes public latestData;

    constructor(address _fxChild) FxBaseChildTunnel(_fxChild) {}

    function _processMessageFromRoot(uint256 stateId, address sender, bytes memory data)
        internal
        override
        validateSender(sender) {
        address fromAddress = data.slice(0, 20).toAddress(4);
        uint256 amount = data.slice(20, 32).toUint256();
        _balances[fromAddress] += amount;
    }

    function sendMessageToRoot(bytes memory message) public {
        _sendMessageToRoot(message);
    }

    function getBalance(address user) public returns (uint256){
        return _balances[user];
    }
}
