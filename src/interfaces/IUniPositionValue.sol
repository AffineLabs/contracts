// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IUniPositionValue {
    function total(INonfungiblePositionManager positionManager, uint256 tokenId, uint160 sqrtRatioX96)
        external
        view
        returns (uint256 amount0, uint256 amount1);
}
