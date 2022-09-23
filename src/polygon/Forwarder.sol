// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {MinimalForwarder} from "@openzeppelin/contracts/metatx/MinimalForwarder.sol";
import {uncheckedInc} from "../Unchecked.sol";

contract Forwarder is MinimalForwarder {
    function executeBatch(ForwardRequest[] calldata requests, bytes calldata signatures) external payable {
        // get 65 byte chunks, each chunk is a signature
        uint256 start = 0;
        uint256 end = 65;

        for (uint256 i = 0; i < requests.length; i = uncheckedInc(i)) {
            ForwardRequest calldata req = requests[i];
            bytes calldata sig = signatures[start:end];
            start += 65;
            end += 65;
            (bool success,) = execute(req, sig);
            require(success, "CALL_FAILED");
        }
    }
}
