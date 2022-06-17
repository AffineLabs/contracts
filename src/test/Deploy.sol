// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { MockERC20 } from "./MockERC20.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { BridgeEscrow } from "../BridgeEscrow.sol";
import { TwoAssetBasket } from "../polygon/TwoAssetBasket.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { L1WormholeRouter } from "../ethereum/L1WormholeRouter.sol";
import { L2WormholeRouter } from "../polygon/L2WormholeRouter.sol";

library Deploy {
    function deployL2Vault() internal returns (L2Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new L2Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            L2WormholeRouter(address(0)), // wormholer router
            BridgeEscrow(address(0)),
            address(0), // forwarder
            1, // l1 ratio
            1, // l2 ratio
            [uint256(0), uint256(200)] // withdrawal and AUM fees
        );
    }

    function deployL1Vault() internal returns (L1Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new L1Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole,
            L1WormholeRouter(address(0)), // wormhole router
            BridgeEscrow(address(0)),
            IRootChainManager(address(0)), // chain manager
            address(0) // predicate
        );
    }

    function deployTwoAssetBasket(ERC20 usdc) internal returns (TwoAssetBasket basket) {
        ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
        ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);
        basket = new TwoAssetBasket(
            address(this), // governance,
            address(0), // forwarder
            10_000 * 1e6, // once the vault is $10,000 out of balance then we can rebalance
            5_000 * 1e6, // selling in $5,000 blocks
            IUniLikeSwapRouter(address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506)), // sushiswap router
            usdc, // mintable usdc
            // WBTC AND WETH
            [btc, weth],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [
                AggregatorV3Interface(0x007A22900a3B98143368Bd5906f8E17e9867581b),
                AggregatorV3Interface(0x0715A7794a1dc8e42615F059dD6e406A6594651A)
            ]
        );
    }
}
