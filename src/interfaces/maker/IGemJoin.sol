// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// https://github.com/makerdao/dss/blob/master/src/join.sol
interface IGemJoin {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function gem() external view returns (address);
    function dec() external view returns (uint256);
    function live() external view returns (uint256);
    function cage() external;
    function join(address usr, uint256 wad) external;
    function exit(address, uint256) external;
}