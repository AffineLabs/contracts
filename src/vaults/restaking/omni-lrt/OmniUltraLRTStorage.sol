// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

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

    // governance address
    address public governance;
    // max wei tolerance,
    // due to lot of calculations and rounding errors
    uint256 public constant WEI_TOLERANCE = 1000;
    // base asset, everything is priced in this asset
    // for eth
    address public baseAsset;

    uint256 public constant MAX_ALLOWED_ASSET = 50;
    // assets list
    address[MAX_ALLOWED_ASSET] public assetList;
    // asset count
    uint256 public assetCount;

    // per asset vault
    mapping(address => address) public vaults;
    // per asset withdrawal queue
    mapping(address => address) public wQueues;
    // per asset price feed
    mapping(address => address) public priceFeeds;

    // locked shares in vaults wqs
    mapping(address => uint256) public minVaultWqEpoch;

    // pause asset
    mapping(address => bool) public pausedAssets;

    // fees
    uint256 public constant MAX_BPS = 10_000;
    uint256 public performanceFeeBps;
    uint256 public managementFeeBps;
    uint256 public withdrawalFeeBps;

    // storage gap
    uint256[50] private __gap;

    // modifier check for valid token
    function _isValidToken(address _token) internal view {
        _isNonZeroAddress(_token);
        if (vaults[_token] == address(0)) {
            revert ReStakingErrors.InvalidToken();
        }
    }

    function _isNonZeroAmount(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert ReStakingErrors.ZeroAmount();
        }
    }

    function _isNonZeroAddress(address _address) internal pure {
        if (_address == address(0)) {
            revert ReStakingErrors.ZeroAddress();
        }
    }

    function _isValidBps(uint256 _bps) internal pure {
        if (_bps > MAX_BPS) {
            revert ReStakingErrors.InvalidFeeBps();
        }
    }
}
