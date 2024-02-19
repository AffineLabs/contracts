// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {BaseVault} from "src/vaults/cross-chain-vault/BaseVault.sol";
import {IRootChainManager} from "src/interfaces/IRootChainManager.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {L2BridgeEscrow} from "src/vaults/cross-chain-vault/escrow/audited/L2BridgeEscrow.sol";
import {L1BridgeEscrow} from "src/vaults/cross-chain-vault/escrow/audited/L1BridgeEscrow.sol";
import {TwoAssetBasket} from "src/vaults/TwoAssetBasket.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {L1WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/audited/L1WormholeRouter.sol";
import {L2WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/audited/L2WormholeRouter.sol";
import {EmergencyWithdrawalQueue} from "src/vaults/cross-chain-vault/EmergencyWithdrawalQueue.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockL2Vault, MockL1Vault, MockL2VaultV2} from "./mocks/index.sol";

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
        L2BridgeEscrow escrow = L2BridgeEscrow(create3.getDeployed(escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(routerSalt));
        EmergencyWithdrawalQueue emergencyWithdrawalQueue = new EmergencyWithdrawalQueue(vault);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(router),
            escrow,
            emergencyWithdrawalQueue,
            [1, 1], // layer ratios
            [uint256(0), uint256(200)], // withdrawal and AUM fees
            [uint256(1_000_000), uint256(100_000)]
        );

        create3.deploy(escrowSalt, abi.encodePacked(type(L2BridgeEscrow).creationCode, abi.encode(address(vault))), 0);
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

    function deployL2VaultV2() internal returns (MockL2VaultV2 vault) {
        Create3Deployer create3 = new Create3Deployer();

        MockERC20 asset = new MockERC20("Mock", "MT", 6);
        vault = new MockL2VaultV2();

        // Deploy helper contracts (escrow and router)
        L2BridgeEscrow escrow = L2BridgeEscrow(create3.getDeployed(escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(routerSalt));
        EmergencyWithdrawalQueue emergencyWithdrawalQueue = new EmergencyWithdrawalQueue(vault);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(router),
            escrow,
            emergencyWithdrawalQueue,
            [1, 1], // layer ratios
            [uint256(0), uint256(200)], // withdrawal and AUM fees
            [uint256(1_000_000), uint256(100_000)]
        );

        create3.deploy(escrowSalt, abi.encodePacked(type(L2BridgeEscrow).creationCode, abi.encode(address(vault))), 0);
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
        L1BridgeEscrow escrow = new L1BridgeEscrow(vault, manager);

        vault.initialize(
            governance, // governance
            asset, // asset
            address(new L1WormholeRouter(vault, IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B))),
            escrow,
            manager, // chain manager
            0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf // predicate (eth mainnet)
        );
    }

    function deployTwoAssetBasket(ERC20 usdc) internal returns (TwoAssetBasket basket) {
        ERC20 btc = ERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);
        ERC20 weth = ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
        basket = new TwoAssetBasket();
        basket.initialize(
            governance, // governance,
            usdc, // mintable usdc
            // WBTC AND WETH
            [btc, weth],
            [uint256(1), uint256(1)], // ratios (basket should contain an equal amount of btc/eth)
            // Price feeds (BTC/USD and ETH/USD)
            [
                AggregatorV3Interface(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7),
                AggregatorV3Interface(0xc907E116054Ad103354f2D350FD2514433D57F6f),
                AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945)
            ]
        );
    }

    function deployEthSSV(ERC20 asset) internal returns (StrategyVault vault) {
        vault = new StrategyVault();
        vault.initialize(governance, address(asset), "Single Strategy Vault", "ETH_SSV_USDC");
    }
}
