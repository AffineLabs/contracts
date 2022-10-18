// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L2Vault} from "../src/polygon/L2Vault.sol";
import {Create3Deployer} from "../src/Create3Deployer.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {IRootChainManager} from "../src/interfaces/IRootChainManager.sol";
import {BridgeEscrow} from "../src/BridgeEscrow.sol";
import {L2WormholeRouter} from "../src/polygon/L2WormholeRouter.sol";
import {Forwarder} from "../src/polygon/Forwarder.sol";
import {EmergencyWithdrawalQueue} from "../src/polygon/EmergencyWithdrawalQueue.sol";

contract Deploy is Script {
    Create3Deployer create3 = Create3Deployer(0x5185fe072f9eE947bF017C7854470e11C2cFb32a);

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
        console.log("not equal: ", escrowSalt != routerSalt);
        require(escrowSalt != routerSalt, "Salts not unique");

        BridgeEscrow escrow = BridgeEscrow(create3.getDeployed(escrowSalt));
        L2WormholeRouter router = L2WormholeRouter(create3.getDeployed(routerSalt));
        EmergencyWithdrawalQueue queue = EmergencyWithdrawalQueue(create3.getDeployed(ewqSalt));

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
                address(new Forwarder()),
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
            abi.encodePacked(type(BridgeEscrow).creationCode, abi.encode(address(vault), IRootChainManager(address(0)))),
            0
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
            ),
            0
        );

        require(router.vault() == vault);
        require(router.wormhole() == wormhole);
        require(router.otherLayerChainId() == uint16(2));

        create3.deploy(ewqSalt, abi.encodePacked(type(EmergencyWithdrawalQueue).creationCode, abi.encode(vault)), 0);
        require(queue.vault() == vault);

        vm.stopBroadcast();
    }
}
