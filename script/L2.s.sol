// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L2Vault} from "../src/polygon/L2Vault.sol";
import {ICREATE3Factory} from "../src/interfaces/ICreate3Factory.sol";
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

contract Deploy is Script {
    ICREATE3Factory create3 = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function _getSaltBasic() internal returns (bytes32 salt) {
        string[] memory inputs = new string[](4);
        inputs[0] = "yarn";
        inputs[1] = "--silent";
        inputs[2] = "ts-node";
        inputs[3] = "scripts/utils/get-bytes.ts";
        bytes memory res = vm.ffi(inputs);
        salt = keccak256(res);
    }

    function _getSaltFile(string memory fileName) internal returns (bytes32 salt) {
        bytes memory saltData = vm.readFileBinary(fileName);
        salt = bytes32(saltData);
    }

    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        // Get salts
        bytes32 escrowSalt = _getSaltFile("salts/escrow.salt");
        bytes32 routerSalt = _getSaltFile("salts/router.salt");
        bytes32 ewqSalt = _getSaltBasic();

        console.logBytes32(escrowSalt);
        console.logBytes32(routerSalt);
        require(escrowSalt != routerSalt, "Salts not unique");

        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(deployer, escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(deployer, routerSalt));
        EmergencyWithdrawalQueue queue = EmergencyWithdrawalQueue(create3.getDeployed(deployer, ewqSalt));
        Forwarder forwarder = new Forwarder();

        // Deploy Vault
        L2Vault impl = new L2Vault();
        bytes memory initData = abi.encodeCall(
            L2Vault.initialize,
            (
                0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0,
                ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174),
                address(router),
                escrow,
                queue,
                address(forwarder),
                9,
                1,
                [uint256(0), uint256(200)] // withdrawal and AUM fees
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        L2Vault vault = L2Vault(address(proxy));
        require(vault.asset() == 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        require(vault.l1Ratio() == 9);
        require(vault.l2Ratio() == 1);
        require(vault.withdrawalFee() == 0);
        require(vault.managementFee() == 200);

        // Deploy helper contracts (escrow, router, and ewq)
        create3.deploy(
            escrowSalt,
            abi.encodePacked(type(BridgeEscrow).creationCode, abi.encode(address(vault), IRootChainManager(address(0))))
        );
        require(escrow.vault() == address(vault));
        require(address(escrow.token()) == vault.asset());
        require(escrow.wormholeRouter() == vault.wormholeRouter());

        IWormhole wormhole = IWormhole(0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7);
        create3.deploy(
            routerSalt,
            abi.encodePacked(
                type(L2WormholeRouter).creationCode,
                abi.encode(
                    vault,
                    wormhole,
                    uint16(2) // ethereum wormhole id is 2
                )
            )
        );
        require(router.vault() == vault);
        require(router.wormhole() == wormhole);
        require(router.otherLayerChainId() == uint16(2));

        create3.deploy(ewqSalt, abi.encodePacked(type(EmergencyWithdrawalQueue).creationCode, abi.encode(vault)));
        require(queue.vault() == vault);

        Router router4626 = new Router("affine-router-v1", address(forwarder));
        require(router4626.trustedForwarder() == address(forwarder));

        TwoAssetBasket basketImpl = new TwoAssetBasket();
        bytes memory basketInitData = abi.encodeCall(
            TwoAssetBasket.initialize,
            (
                0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0, // governance,
                address(forwarder), // forwarder
                IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // sushiswap router
                ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174), // usdc
                // WBTC AND WETH
                [ERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6), ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619)],
                [uint256(1), uint256(1)], // ratios
                // Price feeds (USDC/USDC, BTC/USD, ETH/USD)
                [
                    AggregatorV3Interface(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7),
                    AggregatorV3Interface(0xc907E116054Ad103354f2D350FD2514433D57F6f),
                    AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945)
                ]
            )
        );

        ERC1967Proxy basketProxy = new ERC1967Proxy(address(basketImpl), basketInitData);
        TwoAssetBasket basket = TwoAssetBasket(address(basketProxy));
        require(basket.btc() == ERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6));
        require(basket.weth() == ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619));

        L2AAVEStrategy aave =
        new L2AAVEStrategy(vault, 0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19, address(0), address(0), address(0), address(0));
        require(address(aave.asset()) == vault.asset());
        vm.stopBroadcast();
    }
}
