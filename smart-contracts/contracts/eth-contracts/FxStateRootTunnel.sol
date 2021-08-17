// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import { FxBaseRootTunnel } from '../tunnel/FxBaseRootTunnel.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BytesLib } from '../library/BytesLib';

/** 
 * @title FxStateRootTunnel
 */
contract FxStateRootTunnel is FxBaseRootTunnel {
    using BytesLib for bytes;
    bytes public latestData;

    constructor(address _checkpointManager, address _fxRoot)  FxBaseRootTunnel(_checkpointManager, _fxRoot) {}

    function _processMessageFromChild(bytes memory data) internal override {
        latestData = data;
    }

    function sendMessageToChild(bytes memory message) public {
        _sendMessageToChild(message);
    }

    function deposit(address tokenAddr, uint256 amount) public {
        IERC20 token = IERC20(tokenAddr);
        token.transferFrom(msg.sender, address(this), amount);
        sendMessageToChild(abi.encodePacked(address(msg.sender)).concat(abi.encodePacked(amount))); 
    }
}
