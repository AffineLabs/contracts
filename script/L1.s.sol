// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import "../src/ethereum/L1Vault.sol";
import {Create3Deployer} from "../src/Create3Deployer.sol";

contract Deploy is Script {
    Create3Deployer create3 = Create3Deployer(0x10A4aA784D2bE45e6e67B909c5cf7E588aA7A257);

    function getSalt(string memory fileName) internal returns (bytes32 salt) {
        string[] memory inputs = new string[](3);
        inputs[0] = "echo";
        inputs[1] = "-n";
        inputs[2] = "random";
 

        bytes memory res = vm.ffi(inputs);
        salt = keccak256(bytes(res));
    }

    function run() external {
        vm.startBroadcast();
        // Get salts
        bytes32 escrowSalt = getSalt("escrow.txt");
        bytes32 routerSalt = getSalt("router.txt");
        bytes32 ewqSalt = getSalt("ewq.txt");

        // bytes32 escrowSalt = keccak256("ab");
        // bytes32 routerSalt = keccak256("abcd");
        // bytes32 ewqSalt = keccak256("abc-d-e-f");

        require(escrowSalt != routerSalt && routerSalt != ewqSalt && escrowSalt != ewqSalt, "Salts not unique");

        address deployed = create3.getDeployed(routerSalt);
        console.log("deployed: %s", deployed);

        // Deploy L1Vault
        L1Vault impl = new L1Vault();
        bytes memory initData = abi.encodeCall(
            L1Vault.initialize,
            (
                address(0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e),
                ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
                create3.getDeployed(routerSalt),
                BridgeEscrow(create3.getDeployed(escrowSalt)),
                IRootChainManager(0xA0c68C638235ee32657e8f720a23ceC1bFc77C77),
                0x9923263fA127b3d1484cFD649df8f1831c2A74e4
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        require(L1Vault(address(proxy)).asset() == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.stopBroadcast();
    }
}
