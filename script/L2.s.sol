// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L2Vault} from "../src/polygon/L2Vault.sol";
import {ICREATE3Factory} from "../src/interfaces/ICreate3Factory.sol";
import {CREATE3Factory} from "../src/test/CREATE3Factory.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {IRootChainManager} from "../src/interfaces/IRootChainManager.sol";
import {L2BridgeEscrow} from "../src/polygon/L2BridgeEscrow.sol";
import {L2WormholeRouter} from "../src/polygon/L2WormholeRouter.sol";
import {Forwarder} from "../src/polygon/Forwarder.sol";
import {EmergencyWithdrawalQueue} from "../src/polygon/EmergencyWithdrawalQueue.sol";

import {Router} from "../src/polygon/Router.sol";
import {TwoAssetBasket} from "../src/polygon/TwoAssetBasket.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

import {L2AAVEStrategy} from "../src/polygon/L2AAVEStrategy.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ILendingPoolAddressesProviderRegistry} from "../src/interfaces/aave.sol";

import {DeltaNeutralLpV3} from "../src/polygon/DeltaNeutralLpV3.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Base} from "./Base.sol";

/*  solhint-disable reason-string */
contract Deploy is Script, Base {
    ICREATE3Factory create3;

    function _getSaltFile(string memory fileName) internal returns (bytes32 salt) {
        bytes memory saltData = vm.readFileBinary(fileName);
        salt = bytes32(saltData);
    }

    function _deployVault(
        Base.L2Config memory config,
        L2WormholeRouter router,
        L2BridgeEscrow escrow,
        EmergencyWithdrawalQueue queue,
        Forwarder forwarder
    ) internal returns (L2Vault vault) {
        // Deploy Vault
        L2Vault impl = new L2Vault();

        // Need to declare array in memory to avoud stack too deep error
        uint256[2] memory fees = [config.withdrawFee, config.managementFee];
        uint256[2] memory ewqParams = [config.ewqMinAssets, config.ewqMinFee];

        bytes memory initData = abi.encodeCall(
            L2Vault.initialize,
            (
                config.governance,
                ERC20(config.usdc),
                address(router),
                escrow,
                queue,
                address(forwarder),
                [9, 1],
                fees,
                ewqParams
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = L2Vault(address(proxy));
        require(vault.asset() == config.usdc);
        require(vault.l1Ratio() == 9);
        require(vault.l2Ratio() == 1);
        require(vault.withdrawalFee() == config.withdrawFee);
        require(vault.managementFee() == config.managementFee);
        require(vault.ewqMinFee() == config.ewqMinFee && vault.ewqMinAssets() == config.ewqMinAssets);
    }

    function _deployBasket(Base.L2Config memory config, Forwarder forwarder) internal {
        TwoAssetBasket basketImpl = new TwoAssetBasket();
        bytes memory basketInitData = abi.encodeCall(
            TwoAssetBasket.initialize,
            (
                config.governance,
                address(forwarder),
                ERC20(config.usdc),
                [ERC20(config.wbtc), ERC20(config.weth)],
                [uint256(1), uint256(1)], // ratios
                // Price feeds (USDC/USDC, BTC/USD, ETH/USD)
                [
                    AggregatorV3Interface(config.feeds.usdc),
                    AggregatorV3Interface(config.feeds.wbtc),
                    AggregatorV3Interface(config.feeds.weth)
                ]
            )
        );

        ERC1967Proxy basketProxy = new ERC1967Proxy(address(basketImpl), basketInitData);
        TwoAssetBasket basket = TwoAssetBasket(address(basketProxy));
        require(address(basket.btc()) == config.wbtc);
        require(address(basket.weth()) == config.weth);
        require(address(basket.tokenToOracle(basket.asset())) == config.feeds.usdc);
        require(address(basket.tokenToOracle(basket.btc())) == config.feeds.wbtc);
        require(address(basket.tokenToOracle(basket.weth())) == config.feeds.weth);
    }

    function _deployStrategies(Base.L2Config memory config, L2Vault vault) internal {
        L2AAVEStrategy aave = new L2AAVEStrategy(vault, config.aaveRegistry);
        require(address(aave.asset()) == vault.asset());

        DeltaNeutralLpV3 sslp = new DeltaNeutralLpV3(
            vault,
            0.05e18,
            0.001e18,
            ILendingPoolAddressesProviderRegistry(config.aaveRegistry),
            ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), // wrapped matic
            AggregatorV3Interface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0), // matic/usd price feed
            ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564), 
            INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
            IUniswapV3Pool(0xA374094527e1673A86dE625aa59517c5dE346d32) // WMATIC/USDC
        );
        require(address(sslp.asset()) == vault.asset());
    }

    function run() external {
        bool testnet = vm.envBool("TEST");
        Base.L2Config memory config = abi.decode(_getConfigJson({mainnet: !testnet, layer1: false}), (Base.L2Config));
        console.log("config registry: ", config.aaveRegistry);
        console.log("config usdc: ", config.usdc);

        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // The create3 factory contract (https://github.com/ZeframLou/create3-factory) does not exist on mumbai
        // So we just deploy it here. NOTE: This means rebalances won't work on testnet
        if (testnet) {
            create3 = ICREATE3Factory(address(new CREATE3Factory()));
        } else {
            create3 = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);
        }

        // Get salts
        bytes32 escrowSalt = _getSaltFile("escrow.salt");
        bytes32 routerSalt = _getSaltFile("router.salt");
        bytes32 ewqSalt = _getSalt();

        console.logBytes32(escrowSalt);
        console.logBytes32(routerSalt);
        require(escrowSalt != routerSalt, "Salts not unique");

        L2BridgeEscrow escrow = L2BridgeEscrow(create3.getDeployed(deployer, escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(deployer, routerSalt));
        EmergencyWithdrawalQueue queue = EmergencyWithdrawalQueue(create3.getDeployed(deployer, ewqSalt));
        Forwarder forwarder = new Forwarder();

        L2Vault vault = _deployVault(config, router, escrow, queue, forwarder);

        // Deploy helper contracts (escrow, router, and ewq)
        create3.deploy(escrowSalt, abi.encodePacked(type(L2BridgeEscrow).creationCode, abi.encode(address(vault))));
        require(escrow.vault() == vault);
        require(address(escrow.asset()) == vault.asset());
        require(escrow.wormholeRouter() == vault.wormholeRouter());

        IWormhole wormhole = IWormhole(config.wormhole);
        create3.deploy(routerSalt, abi.encodePacked(type(L2WormholeRouter).creationCode, abi.encode(vault, wormhole)));
        require(router.vault() == vault);
        require(router.wormhole() == wormhole);

        // Deploy Ewq
        create3.deploy(ewqSalt, abi.encodePacked(type(EmergencyWithdrawalQueue).creationCode, abi.encode(vault)));
        require(queue.vault() == vault);

        // Deploy Router
        Router router4626 = new Router("affine-router-v1", address(forwarder));
        require(router4626.trustedForwarder() == address(forwarder));

        // Deploy TwoAssetBasket
        _deployBasket(config, forwarder);

        // Deploy strategies
        if (!testnet) _deployStrategies(config, vault);

        vm.stopBroadcast();
    }
}
