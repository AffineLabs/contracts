// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

// See https://etherscan.io/address/0xa79828df1850e8a3a3064576f380d90aecdd3359#code for an example
interface I3CrvMetaPoolZap {
    function add_liquidity(address pool, uint256[4] memory depositAmounts, uint256 minMintAmount)
        external
        returns (uint256);

    function calc_withdraw_one_coin(address pool, uint256 _token_amount, int128 i) external returns (uint256);
}
