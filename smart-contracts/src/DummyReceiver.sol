// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;

interface IWormhole {
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint8 guardianIndex;
    }

    struct VM {
        uint8 version;
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
        uint32 guardianSetIndex;
        Signature[] signatures;
        bytes32 hash;
    }

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    function parseAndVerifyVM(bytes calldata encodedVM)
        external
        view
        returns (
            VM memory vm,
            bool valid,
            string memory reason
        );
}

contract DummyReceiver {
    IWormhole public wormhole;
    uint256 public tvl;

    constructor(address wormhole_) {
        wormhole = IWormhole(wormhole_);
    }

    // This is the VAA we received from a wormhole guardian
    function receiveMessage(bytes calldata message) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(message);
        require(valid, reason);

        // TODO: check chain ID, emitter address

        // get tvl from payload
        tvl = abi.decode(vm.payload, (uint256));
    }
}
