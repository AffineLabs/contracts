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

contract Deploy is Script {
    Create3Deployer create3 = Create3Deployer(0x10A4aA784D2bE45e6e67B909c5cf7E588aA7A257);

    function _getSalt() internal returns (bytes32 salt) {
        string[] memory inputs = new string[](4);
        inputs[0] = "yarn";
        inputs[1] = "--silent";
        inputs[2] = "ts-node";
        inputs[3] = "scripts/utils/get-bytes.ts";
        bytes memory res = vm.ffi(inputs);
        salt = keccak256(res);
    }

    function run() external {
        (address deployer, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        // Get salts
        bytes32 escrowSalt = _getSalt();
        bytes32 routerSalt = _getSalt();
        require(escrowSalt != routerSalt, "Salts not unique");

        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(escrowSalt));
        L1WormholeRouter router = L1WormholeRouter(create3.getDeployed(routerSalt));

        // Deploy L1Vault
        L1Vault impl = new L1Vault();
        bytes memory initData = abi.encodeCall(
            L1Vault.initialize,
            (
                address(0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e),
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

        vm.stopBroadcast();
    }
}
