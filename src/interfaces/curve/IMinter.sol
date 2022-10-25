// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

// See https://etherscan.io/address/0xd8b712d29381748dB89c36BCa0138d7c75866ddF#code
/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
interface IMinter {
    function mint(address gauge) external;
}

/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
