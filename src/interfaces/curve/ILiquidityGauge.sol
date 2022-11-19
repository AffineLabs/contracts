// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// See https://etherscan.io/address/0xd8b712d29381748dB89c36BCa0138d7c75866ddF#code
/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
interface ILiquidityGauge {
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external returns (uint256);
    function claimable_tokens(address addr) external returns (uint256);
    function claim_rewards() external;
    function balanceOf(address owner) external returns (uint256);
}

/*  solhint-disable func-name-mixedcase, var-name-mixedcase */
