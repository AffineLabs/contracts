// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract KovanClient is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    uint256 public result;

    constructor() {
        setChainlinkToken(0xa36085F69e2889c224210F603D836748e7dC0088);
        oracle = 0xaE045Ec792F54811efa4d53206Cb36DA8cE7D734;
        jobId = "4ed8709ffe584ebfb401e2a2efb1251d";
        fee = 0.01 * 10**18; // amount of link we pay for each request
    }

    /**
     * Initial request
     */
    function requestDepositTokenPrice() public {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillDepositTokenPrice.selector
        );
        sendChainlinkRequestTo(oracle, req, fee);
    }

    /**
     * Callback function
     */
    function fulfillDepositTokenPrice(bytes32 _requestId, uint256 _result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        result = _result;
    }

    // TODO: make this onlyOwner
    function withdrawLink() public {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());

        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
