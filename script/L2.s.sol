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
import {BridgeEscrow} from "../src/BridgeEscrow.sol";
import {L2WormholeRouter} from "../src/polygon/L2WormholeRouter.sol";
import {Forwarder} from "../src/polygon/Forwarder.sol";
import {EmergencyWithdrawalQueue} from "../src/polygon/EmergencyWithdrawalQueue.sol";
import {Router} from "../src/polygon/Router.sol";
import {TwoAssetBasket} from "../src/polygon/TwoAssetBasket.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {L2AAVEStrategy} from "../src/polygon/L2AAVEStrategy.sol";

import {Base} from "./Base.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }
}

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
        BridgeEscrow escrow,
        EmergencyWithdrawalQueue queue,
        Forwarder forwarder
    ) internal returns (L2Vault vault) {
        // Deploy Vault
        L2Vault impl = new L2Vault();
        // Need to declare array in memory to avoud stack too deep error
        uint256[2] memory fees = [config.withdrawFee, config.managementFee]; // withdrawal and AUM fees;
        bytes memory initData = abi.encodeCall(
            L2Vault.initialize,
            (config.governance, ERC20(config.usdc), address(router), escrow, queue, address(forwarder), 9, 1, fees)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = L2Vault(address(proxy));
        require(vault.asset() == config.usdc);
        require(vault.l1Ratio() == 9);
        require(vault.l2Ratio() == 1);
        require(vault.withdrawalFee() == config.withdrawFee);
        require(vault.managementFee() == config.managementFee);
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
    }

    function run() external {
        bool testnet = vm.envBool("TEST");
        Base.L2Config memory config = abi.decode(_getConfigJson({mainnet: !testnet, layer1: false}), (Base.L2Config));
        console.log("config registry: ", config.aaveRegistry);
        console.log("config usdc: ", config.usdc);

        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console.log("deployer", deployer);

        {
            MockERC20 btc = MockERC20(0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509);
            MockERC20 weth = MockERC20(0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61);
            btc.mint(deployer, 5000 * 1e18);
            weth.mint(deployer, 100_000 * 1e18);
            IUniswapV2Router02 uni = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
            uni.addLiquidity(
                address(btc), address(weth), 5000 * 1e18, 100_000 * 1e18, 0, 0, address(this), block.timestamp * 2
            );
            address res = IUniswapV2Factory(uni.factory()).getPair(address(btc), address(weth));
            console.log("pair", res);
            console.log("btc amount", btc.balanceOf(res));
            console.log("eth amount", weth.balanceOf(res));
        }
        return;

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

        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(deployer, escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(deployer, routerSalt));
        EmergencyWithdrawalQueue queue = EmergencyWithdrawalQueue(create3.getDeployed(deployer, ewqSalt));
        Forwarder forwarder = new Forwarder();

        L2Vault vault = _deployVault(config, router, escrow, queue, forwarder);

        // Deploy helper contracts (escrow, router, and ewq)
        create3.deploy(
            escrowSalt,
            abi.encodePacked(type(BridgeEscrow).creationCode, abi.encode(address(vault), IRootChainManager(address(0))))
        );
        require(escrow.vault() == address(vault));
        require(address(escrow.token()) == vault.asset());
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
