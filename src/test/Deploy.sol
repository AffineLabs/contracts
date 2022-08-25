// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Test } from "forge-std/Test.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseVault } from "../BaseVault.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { BridgeEscrow } from "../BridgeEscrow.sol";
import { TwoAssetBasket } from "../polygon/TwoAssetBasket.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { L1WormholeRouter } from "../ethereum/L1WormholeRouter.sol";
import { L2WormholeRouter } from "../polygon/L2WormholeRouter.sol";
import { EmergencyWithdrawalQueue } from "../polygon/EmergencyWithdrawalQueue.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockL2Vault } from "./mocks/index.sol";

contract Deploy is Test {
    address governance = makeAddr("governance");

    function deployL2Vault() internal returns (MockL2Vault vault) {
        MockERC20 asset = new MockERC20("Mock", "MT", 6);
        vault = new MockL2Vault();
        EmergencyWithdrawalQueue emergencyWithdrawalQueue = new EmergencyWithdrawalQueue(governance);
        BridgeEscrow escrow = new BridgeEscrow(address(this));
        vault.initialize(
            governance, // governance
            asset, // asset
            address(new L2WormholeRouter()),
            escrow,
            emergencyWithdrawalQueue,
            address(0), // forwarder
            1, // l1 ratio
            1, // l2 ratio
            [uint256(0), uint256(200)] // withdrawal and AUM fees
        );
        vm.prank(governance);
        vault.setAssetLimit(type(uint256).max);

        escrow.initialize(address(vault), address(vault.wormholeRouter()), asset, IRootChainManager(address(0)));
        emergencyWithdrawalQueue.linkVault(vault);
    }

    function deployL1Vault() internal returns (L1Vault vault) {
        // For polygon addresses, see
        // solhint-disable-next-line max-line-length
        // https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deploymenthttps://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deployment
        MockERC20 asset = new MockERC20("Mock", "MT", 6);
        vault = new L1Vault();
        BridgeEscrow escrow = new BridgeEscrow(address(this));
        IRootChainManager manager = IRootChainManager(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(new L1WormholeRouter()),
            escrow,
            manager, // chain manager
            0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf // predicate (eth mainnet)
        );

        escrow.initialize(address(vault), address(vault.wormholeRouter()), asset, manager);
    }

    function deployTwoAssetBasket(ERC20 usdc) internal returns (TwoAssetBasket basket) {
        ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
        ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);
        basket = new TwoAssetBasket();
        basket.initialize(
            governance, // governance,
            address(0), // forwarder
            IUniLikeSwapRouter(address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506)), // sushiswap router
            usdc, // mintable usdc
            // WBTC AND WETH
            [btc, weth],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [
                AggregatorV3Interface(0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0),
                AggregatorV3Interface(0x007A22900a3B98143368Bd5906f8E17e9867581b),
                AggregatorV3Interface(0x0715A7794a1dc8e42615F059dD6e406A6594651A)
            ]
        );

        vm.prank(governance);
        basket.setAssetLimit(type(uint256).max);
    }
}
