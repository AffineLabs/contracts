// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

// See https://etherscan.io/address/0xa79828df1850e8a3a3064576f380d90aecdd3359#code for an example
/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
interface I3CrvMetaPoolZap {
    function add_liquidity(address pool, uint256[4] memory depositAmounts, uint256 minMintAmount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(address _pool, uint256 _burn_amount, int128 i, uint256 _min_amount)
        external
        returns (uint256);

    function remove_liquidity_imbalance(address _pool, uint256[4] memory _amounts, uint256 _max_burn_amount)
        external
        returns (uint256);

    function calc_withdraw_one_coin(address pool, uint256 _token_amount, int128 i) external view returns (uint256);
}
/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
