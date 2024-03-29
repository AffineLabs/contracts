// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// https://github.com/makerdao/dss-cdp-manager/
// dss-interfaces
interface ICdpManager {
    function vat() external view returns (address);
    function cdpi() external view returns (uint256);
    function urns(uint256) external view returns (address);
    function list(uint256) external view returns (uint256, uint256);
    function owns(uint256) external view returns (address);
    function ilks(uint256) external view returns (bytes32);
    function first(address) external view returns (uint256);
    function last(address) external view returns (uint256);
    function count(address) external view returns (uint256);
    function cdpCan(address, uint256, address) external returns (uint256);
    function urnCan(address, address) external returns (uint256);
    function cdpAllow(uint256, address, uint256) external;
    function urnAllow(address, uint256) external;
    function open(bytes32, address) external returns (uint256);
    function give(uint256, address) external;
    function frob(uint256, int256, int256) external;
    function flux(uint256 cdp, address dst, uint256 wad) external;
    function flux(bytes32, uint256, address, uint256) external;
    function move(uint256 cdp, address dst, uint256 rad) external;
    function quit(uint256, address) external;
    function enter(address, uint256) external;
    function shift(uint256, uint256) external;
}
