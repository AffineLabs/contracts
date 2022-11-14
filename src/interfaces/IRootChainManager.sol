// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

interface IRootChainManager {
    function depositFor(address user, address rootToken, bytes calldata depositData) external;

    function exit(bytes memory _data) external;
}
