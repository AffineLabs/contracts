// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

interface IWormhole {
    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);
}

contract DummyBridge {
    IWormhole public wormhole;
    uint256 public tvl;
    uint32 public nonce;

    constructor(address wormhole_, uint256 tvl_) {
        wormhole = IWormhole(wormhole_);
        tvl = tvl_;
    }

    function sendTVL() public {
        bytes memory payload = abi.encodePacked(tvl);
        // 4 ETH blocks will take about 1 minute to propagate
        // using 1 for testing
        wormhole.publishMessage(nonce, payload, 1);
        nonce += 1;
    }

    function changeTVL(uint256 newTVL) public {
        tvl = newTVL;
    }
}
