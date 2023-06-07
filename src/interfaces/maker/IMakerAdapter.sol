// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;
// See MCD_JOIN_CRVV1ETHSTETH_A at  https://etherscan.io/address/0x82D8bfDB61404C796385f251654F6d7e92092b5D#code
// https://github.com/makerdao/dss-crop-join/blob/master/src/CropJoin.sol
interface IMakerAdapter {

// MCD_JOIN_CRVV1ETHSTETH_A takes an extra urn param. This is different from the other adapters. See the typical adapter
// at https://github.com/makerdao/dss-interfaces/blob/9bfd7afadd1f8c217ef05850b2555691786286cb/src/dss/DaiJoinAbstract.sol
function join(address urn, address usr, uint256 val) external;
function exit(address usr, uint256 val) external;
}
