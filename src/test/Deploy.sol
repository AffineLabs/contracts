// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { MockERC20 } from "./MockERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { Relayer } from "../polygon/Relayer.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { IStaging } from "../interfaces/IStaging.sol";
import { IL1WormholeRouter, IL2WormholeRouter } from "../interfaces/IWormholeRouter.sol";

library Deploy {
    function deployL2Vault() internal returns (L2Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        Relayer relayer = new Relayer();

        vault = new L2Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            IL2WormholeRouter(address(0)), // Wormhole router
            IStaging(address(0)),
            1, // l1 ratio
            1, // l2 ratio
            relayer, // relayer
            [uint256(0), uint256(200)] // withdrawal and AUM fees
        );

        relayer.initialize(address(0), vault);
    }

    function deployL1Vault() internal returns (L1Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new L1Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole,
            IL1WormholeRouter(address(0)), // Wormhole router
            IStaging(address(0)),
            IRootChainManager(address(0)), // chain manager
            address(0) // predicate
        );
    }

    function deployBaseVault() internal returns (BaseVault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        vault = new BaseVault();
        vault.init(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            IStaging(address(0))
        );
    }
}
