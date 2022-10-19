// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L1Vault} from "../src/ethereum/L1Vault.sol";
import {Create3Deployer} from "../src/Create3Deployer.sol";
import {IRootChainManager} from "../src/interfaces/IRootChainManager.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {BridgeEscrow} from "../src/BridgeEscrow.sol";
import {L1WormholeRouter} from "../src/ethereum/L1WormholeRouter.sol";

import {L1CompoundStrategy} from "../src/ethereum/L1CompoundStrategy.sol";
import {ICToken} from "../src/interfaces/compound/ICToken.sol";
import {IComptroller} from "../src/interfaces/compound/IComptroller.sol";
import {L1CompoundStrategy} from "../src/ethereum/L1CompoundStrategy.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {CurveStrategy} from "../src/ethereum/CurveStrategy.sol";
import {I3CrvMetaPoolZap} from "../src/interfaces/IMetaPoolZap.sol";
import {ILiquidityGauge} from "../src/interfaces/ILiquidityGauge.sol";

import {ConvexUSDCStrategy} from "../src/ethereum/ConvexUSDCStrategy.sol";
import {ICurveUSDCStableSwapZap} from "../src/interfaces/curve/ICurveUSDCStableSwapZap.sol";
import {IConvexBooster} from "../src/interfaces/convex/IConvexBooster.sol";
import {IConvexClaimZap} from "../src/interfaces/convex/IConvexClaimZap.sol";
import {IConvexCrvRewards} from "../src/interfaces/convex/IConvexCrvRewards.sol";


contract Deploy is Script {
    Create3Deployer create3 = Create3Deployer(0x10A4aA784D2bE45e6e67B909c5cf7E588aA7A257);

    function _getSalt(string memory fileName) internal returns (bytes32 salt) {
        string[] memory inputs = new string[](4);
        inputs[0] = "yarn";
        inputs[1] = "--silent";
        inputs[2] = "ts-node";
        inputs[3] = "scripts/utils/get-bytes.ts";
        bytes memory res = vm.ffi(inputs);
        salt = keccak256(res);
        console.log("about to log bytes salt");
        console.logBytes(abi.encodePacked(salt));
        vm.writeFileBinary(fileName, abi.encodePacked(salt));
    }

    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        // Get salts
        bytes32 escrowSalt = _getSalt("salts/escrow.salt");
        bytes32 routerSalt = _getSalt("salts/router.salt");
        require(escrowSalt != routerSalt, "Salts not unique");

        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(escrowSalt));
        L1WormholeRouter router = L1WormholeRouter(create3.getDeployed(routerSalt));

        // Deploy L1Vault
        L1Vault impl = new L1Vault();
        bytes memory initData = abi.encodeCall(
            L1Vault.initialize,
            (
                0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e,
                ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
                address(router),
                escrow,
                IRootChainManager(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77),
                0x9923263fA127b3d1484cFD649df8f1831c2A74e4
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        L1Vault vault = L1Vault(address(proxy));
        require(vault.asset() == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Deploy helper contracts (escrow and router)
        create3.deploy(
            escrowSalt,
            abi.encodePacked(
                type(BridgeEscrow).creationCode,
                abi.encode(address(vault), IRootChainManager(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77))
            ),
            0
        );

        require(escrow.vault() == address(vault));
        require(address(escrow.token()) == vault.asset());
        require(escrow.wormholeRouter() == vault.wormholeRouter());

        IWormhole wormhole = IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);
        create3.deploy(
            routerSalt,
            abi.encodePacked(
                type(L1WormholeRouter).creationCode,
                abi.encode(
                    vault,
                    wormhole,
                    uint16(5) // polygon wormhole id is 5
                )
            ),
            0
        );

        require(router.vault() == vault);
        require(router.wormhole() == wormhole);
        require(router.otherLayerChainId() == uint16(5));


        // Compound strat
        L1CompoundStrategy comp = new L1CompoundStrategy(vault, ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563), 
        IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B), IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D),
        0xc00e94Cb662C3520282E6f5717214004A7f26888, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        require(address(comp.asset()) == vault.asset());

        // Curve Strat
        CurveStrategy curve = new CurveStrategy(vault, 
                         ERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B),
                         I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359), 
                         2,
                         ILiquidityGauge(0xd8b712d29381748dB89c36BCa0138d7c75866ddF),
                         IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D),
                         ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52)
                         );
        require(address(curve.asset()) == vault.asset());

        // Convex strat
        ConvexUSDCStrategy cvx = new ConvexUSDCStrategy(
            vault, 
            ICurveUSDCStableSwapZap(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2),
            100,
            IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31),
            IConvexClaimZap(0xDd49A93FDcae579AE50B4b9923325e9e335ec82B),
            IConvexCrvRewards(0x7e880867363A7e321f5d260Cade2B0Bb2F717B02),
            IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)
        );
        require(address(cvx.asset()) == vault.asset()); 

        vm.stopBroadcast();
    }
}
