// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { MockERC20 } from "./MockERC20.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { Staging } from "../Staging.sol";
import { TwoAssetBasket } from "../polygon/TwoAssetBasket.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

library Deploy {
    function deployL2Vault() internal returns (L2Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new L2Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            Staging(address(0)),
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
            IWormhole(address(0)), // wormhole, // wormhole
            Staging(address(0)),
            IRootChainManager(address(0)), // chain manager
            address(0) // predicate
        );
    }

    function deployBaseVault() internal returns (BaseVault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new BaseVault();
        vault.init(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            Staging(address(0))
        );
    }

    function deployTwoAssetBasket(ERC20 usdc) internal returns (TwoAssetBasket basket) {
        MockERC20 btc = new MockERC20("Mock BTC", "mBTC", 18);
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH", 18);
        basket = new TwoAssetBasket(
            address(this), // governance,
            address(0), // forwarder
            10_000 * 1e6, // once the vault is $10,000 out of balance then we can rebalance
            5_000 * 1e6, // selling in $5,000 blocks
            IUniLikeSwapRouter(address(0)), // sushiswap router
            usdc, // mintable usdc
            // WBTC AND WETH
            [ERC20(btc), ERC20(weth)],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [AggregatorV3Interface(address(0)), AggregatorV3Interface(address(0))]
        );
    }
}
