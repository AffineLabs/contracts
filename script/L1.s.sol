// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L1Vault} from "../src/ethereum/L1Vault.sol";
import {ICREATE3Factory} from "../src/interfaces/ICreate3Factory.sol";
import {IRootChainManager} from "../src/interfaces/IRootChainManager.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {L1BridgeEscrow} from "../src/ethereum/L1BridgeEscrow.sol";
import {L1WormholeRouter} from "../src/ethereum/L1WormholeRouter.sol";

import {L1CompoundStrategy} from "../src/ethereum/L1CompoundStrategy.sol";
import {ICToken} from "../src/interfaces/compound/ICToken.sol";
import {IComptroller} from "../src/interfaces/compound/IComptroller.sol";
import {L1CompoundStrategy} from "../src/ethereum/L1CompoundStrategy.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {CurveStrategy} from "../src/ethereum/CurveStrategy.sol";
import {I3CrvMetaPoolZap, ILiquidityGauge, ICurvePool, IMinter} from "../src/interfaces/curve.sol";

import {ConvexStrategy} from "../src/ethereum/ConvexStrategy.sol";
import {ICurvePool} from "../src/interfaces/curve.sol";
import {IConvexBooster, IConvexRewards} from "../src/interfaces/convex.sol";

import {DeltaNeutralLp} from "../src/DeltaNeutralLp.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "../src/interfaces/aave.sol";
import {IMasterChef} from "../src/interfaces/sushiswap/IMasterChef.sol";

import {Base} from "./Base.sol";

/*  solhint-disable reason-string */
contract Deploy is Script, Base {
    using stdJson for string;

    ICREATE3Factory create3 = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function _getSaltAndWrite(string memory fileName) internal returns (bytes32 salt) {
        salt = _getSalt();
        console.log("about to log bytes salt");
        console.logBytes(abi.encodePacked(salt));
        vm.writeFileBinary(fileName, abi.encodePacked(salt));
    }

    function _deployStrategies(L1Vault vault) internal {
        // Compound strat
        L1CompoundStrategy comp = new L1CompoundStrategy(vault, ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563));
        require(address(comp.asset()) == vault.asset());

        // Curve Strat
        CurveStrategy curve = new CurveStrategy(vault, 
                         ERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B),
                         I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359), 
                         2,
                         ILiquidityGauge(0xd8b712d29381748dB89c36BCa0138d7c75866ddF)
                         );
        require(address(curve.asset()) == vault.asset());

        // Convex strat
        ConvexStrategy cvx = new ConvexStrategy(
           vault, 
            ICurvePool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2),
            100,
            IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31));
        require(address(cvx.asset()) == vault.asset());

        // SSLP strat
        uint256 longPct = 10 ** 15;
        uint256 masterChefPID = 1;
        DeltaNeutralLp dnlp = new DeltaNeutralLp(
           vault, 
            longPct,
            ILendingPoolAddressesProviderRegistry(0x52D306e36E3B6B02c153d0266ff0f85d18BCD413),
            ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // Asset to borrow (WETH)
            AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
            IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F),
            IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd),
            masterChefPID,
            false,
            ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2));
        require(address(dnlp.asset()) == vault.asset());
    }

    function run() external {
        bool testnet = vm.envBool("TEST");
        console.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));
        console.log("config usdc: ", config.usdc);

        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        // Get salts
        bytes32 escrowSalt = _getSaltAndWrite("escrow.salt");
        bytes32 routerSalt = _getSaltAndWrite("router.salt");
        require(escrowSalt != routerSalt, "Salts not unique");

        L1BridgeEscrow escrow = L1BridgeEscrow(create3.getDeployed(deployer, escrowSalt));
        L1WormholeRouter router = L1WormholeRouter(create3.getDeployed(deployer, routerSalt));

        // Deploy L1Vault
        L1Vault impl = new L1Vault();
        bytes memory initData = abi.encodeCall(
            L1Vault.initialize,
            (
                config.governance,
                ERC20(config.usdc),
                address(router),
                escrow,
                IRootChainManager(config.chainManager),
                config.erc20Predicate
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        L1Vault vault = L1Vault(address(proxy));
        require(vault.asset() == config.usdc);
        require(vault.governance() == config.governance);
        require(address(vault.chainManager()) == config.chainManager);
        require(vault.predicate() == config.erc20Predicate);

        // Deploy helper contracts (escrow and router)
        create3.deploy(
            escrowSalt,
            abi.encodePacked(
                type(L1BridgeEscrow).creationCode, abi.encode(address(vault), IRootChainManager(config.chainManager))
            )
        );
        require(escrow.vault() == vault);
        require(address(escrow.asset()) == vault.asset());
        require(escrow.wormholeRouter() == vault.wormholeRouter());
        require(vault.chainManager() == escrow.rootChainManager());

        IWormhole wormhole = IWormhole(config.wormhole);
        create3.deploy(routerSalt, abi.encodePacked(type(L1WormholeRouter).creationCode, abi.encode(vault, wormhole)));

        require(router.vault() == vault);
        require(router.wormhole() == wormhole);

        if (!testnet) _deployStrategies(vault);
        vm.stopBroadcast();
    }
}
