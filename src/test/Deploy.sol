// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {BaseVault} from "../BaseVault.sol";
import {IRootChainManager} from "../interfaces/IRootChainManager.sol";
import {L1Vault} from "../ethereum/L1Vault.sol";
import {BridgeEscrow} from "../BridgeEscrow.sol";
import {TwoAssetBasket} from "../polygon/TwoAssetBasket.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IWormhole} from "../interfaces/IWormhole.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {L1WormholeRouter} from "../ethereum/L1WormholeRouter.sol";
import {L2WormholeRouter} from "../polygon/L2WormholeRouter.sol";
import {EmergencyWithdrawalQueue} from "../polygon/EmergencyWithdrawalQueue.sol";
import {Create3Deployer} from "../Create3Deployer.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockL2Vault, MockL1Vault} from "./mocks/index.sol";

contract Deploy is Test {
    address governance = makeAddr("governance");
    bytes32 escrowSalt = keccak256("escrow");
    bytes32 ewqSalt = keccak256("ewq");
    bytes32 routerSalt = keccak256("router");

    function deployL2Vault() internal returns (MockL2Vault vault) {
        Create3Deployer create3 = new Create3Deployer();

        MockERC20 asset = new MockERC20("Mock", "MT", 6);
        vault = new MockL2Vault();

        // Deploy helper contracts (escrow and router)
        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(routerSalt));
        EmergencyWithdrawalQueue emergencyWithdrawalQueue = new EmergencyWithdrawalQueue(vault);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(router),
            escrow,
            emergencyWithdrawalQueue,
            address(0), // forwarder
            1, // l1 ratio
            1, // l2 ratio
            [uint256(0), uint256(200)] // withdrawal and AUM fees
        );

        create3.deploy(
            escrowSalt,
            abi.encodePacked(type(BridgeEscrow).creationCode, abi.encode(address(vault), IRootChainManager(address(0)))),
            0
        );
        create3.deploy(
            routerSalt,
            abi.encodePacked(
                type(L2WormholeRouter).creationCode,
                abi.encode(
                    vault,
                    IWormhole(0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7),
                    uint16(2) // ethereum wormhole id is 2
                )
            ),
            0
        );
    }

    function deployL1Vault() internal returns (MockL1Vault vault) {
        // For polygon addresses, see
        // solhint-disable-next-line max-line-length
        // https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deploymenthttps://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deployment
        MockERC20 asset = new MockERC20("Mock", "MT", 6);
        vault = new MockL1Vault();

        IRootChainManager manager = IRootChainManager(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77);
        BridgeEscrow escrow = new BridgeEscrow(address(vault), manager);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(new L1WormholeRouter(vault, IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B), uint16(0))),
            escrow,
            manager, // chain manager
            0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf // predicate (eth mainnet)
        );
    }

    function deployTwoAssetBasket(ERC20 usdc) internal returns (TwoAssetBasket basket) {
        ERC20 btc = ERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
        ERC20 weth = ERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);
        basket = new TwoAssetBasket();
        basket.initialize(
            governance, // governance,
            address(0), // forwarder
            IUniswapV2Router02(address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506)), // sushiswap router
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
    }
}
