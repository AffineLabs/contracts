// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { MockERC20 } from "./MockERC20.sol";

import { L2Vault } from "../polygon/L2Vault.sol";
import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { Create2Deployer } from "./Create2Deployer.sol";
import { Relayer } from "../polygon/Relayer.sol";
import { L1Vault } from "../ethereum/L1Vault.sol";
import { WithdrawalQueue } from "../polygon/WithdrawalQueue.sol";
import { WormholeRouter } from "../polygon/WormholeRouter.sol";

library Deploy {
    function deployL2Vault() internal returns (L2Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        Create2Deployer create2Deployer = new Create2Deployer();

        Relayer relayer = new Relayer();

        vault = new L2Vault();
        WithdrawalQueue withdrawalQueue = new WithdrawalQueue(address(this), token);
        WormholeRouter wormholeRouter = new WormholeRouter();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            address(wormholeRouter),
            create2Deployer, // create2deployer (needs to be a real contract)
            withdrawalQueue,
            1, // l1 ratio
            1, // l2 ratio
            relayer, // relayer
            [uint256(0), uint256(200)] // withdrawal and AUM fees
        );
        withdrawalQueue.addVault(address(vault));
        relayer.initialize(address(0), vault);
    }

    function deployL1Vault() internal returns (L1Vault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        Create2Deployer create2Deployer = new Create2Deployer();

        vault = new L1Vault();
        vault.initialize(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole, // wormhole
            create2Deployer, // create2deployer (must be real address)
            IRootChainManager(address(0)), // chain manager
            address(0) // predicate
        );
    }

    function deployBaseVault() internal returns (BaseVault vault) {
        MockERC20 token = new MockERC20("Mock", "MT", 18);
        Create2Deployer create2Deployer = new Create2Deployer();

        vault = new BaseVault();
        vault.init(
            address(this), // governance
            token, // token
            IWormhole(address(0)), // wormhole
            create2Deployer // create2deployer (needs to be a real contract)
        );
    }
}
