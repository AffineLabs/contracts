// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface IRootChainManager {
    function depositFor(address user, address rootToken, bytes calldata depositData) external;

    function exit(bytes memory _data) external;
}
