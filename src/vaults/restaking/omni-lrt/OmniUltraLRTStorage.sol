// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

abstract contract OmniUltraLRTStorage {
    // gov role
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GUARDIAN_ROLE");
    // harvester role
    // manage harvesting, managing assets, and fees
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    // manager role
    // can manage pause unpause contracts or pause deposits, withdrawals
    // can pause specific assets too
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // base asset, everything is priced in this asset
    // for eth
    address public baseAsset;

    // assets list
    address[50] public assets;
    // asset count
    uint256 public assetCount;

    // per asset vault
    mapping(address => address) public vaults;
    // per asset withdrawal queue
    mapping(address => address) public wQueues;
    // per asset price feed
    mapping(address => address) public priceFeeds;

    // pause asset
    mapping(address => bool) public pausedAssets;

    // fees
    uint256 public constant MAX_BPS = 10_000;
    uint256 public performanceFeeBps;
    uint256 public managementFeeBps;
    uint256 public withdrawalFeeBps;

    // storage gap
    uint256[50] private __gap;
}
