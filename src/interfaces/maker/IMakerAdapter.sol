// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// See MCD_CROPPER at https://etherscan.io/address/0x8377CD01a5834a6EaD3b7efb482f678f2092b77e#code
// Crop is MCD_JOIN_CRVV1ETHSTETH_A
interface ICropper {
    function join(address crop, address usr, uint256 val) external;
    function frob(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) external;
    function move(address u, address dst, uint256 rad) external;
}
interface IMakerAdapter {

// See https://github.com/makerdao/dss-crop-join/blob/master/src/CropJoin.sol
// at https://github.com/makerdao/dss-interfaces/blob/9bfd7afadd1f8c217ef05850b2555691786286cb/src/dss/DaiJoinAbstract.sol
function join(address urn, address usr, uint256 val) external;
function exit(address usr, uint256 val) external;
}
