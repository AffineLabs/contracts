// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ILendingPoolAddressesProviderRegistry} from "../interfaces/aave.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {BaseVault} from "../BaseVault.sol";
import {IMasterChef} from "../interfaces/sushiswap/IMasterChef.sol";

import {BaseDeltaNeutralLpStrategy} from "../BaseDeltaNeutralLpStrategy.sol";

contract L1DeltaNeutralLp is BaseDeltaNeutralLpStrategy {
    constructor(
        BaseVault _vault,
        uint256 _longPct,
        ILendingPoolAddressesProviderRegistry _registry,
        ERC20 _borrowAsset,
        AggregatorV3Interface _borrowAssetFeed,
        IUniswapV2Router02 _router,
        IMasterChef _masterChef,
        uint256 _masterChefPid
    )
        BaseDeltaNeutralLpStrategy(
            _vault,
            _longPct,
            _registry,
            _borrowAsset,
            _borrowAssetFeed,
            _router,
            _masterChef,
            _masterChefPid
        )
    {}
}
