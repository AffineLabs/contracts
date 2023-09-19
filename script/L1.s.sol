// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {ICREATE3Factory} from "src/interfaces/ICreate3Factory.sol";
import {IRootChainManager} from "src/interfaces/IRootChainManager.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";
import {L1BridgeEscrow} from "src/vaults/cross-chain-vault/escrow/L1BridgeEscrow.sol";
import {L1WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/L1WormholeRouter.sol";

import {L1CompoundStrategy} from "src/strategies/L1CompoundStrategy.sol";
import {ICToken} from "src/interfaces/compound/ICToken.sol";
import {IComptroller} from "src/interfaces/compound/IComptroller.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {DeltaNeutralLp} from "src/strategies/DeltaNeutralLp.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolAddressesProviderRegistry} from "src/interfaces/aave.sol";
import {IMasterChef} from "src/interfaces/sushiswap/IMasterChef.sol";

import {Base, stdJson} from "./Base.sol";

/*  solhint-disable reason-string, no-console */
contract Deploy is Script, Base {
    using stdJson for string;

    ICREATE3Factory create3 = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function _getSaltAndWrite(string memory fileName) internal returns (bytes32 salt) {
        salt = _getSalt();
        console2.log("about to log bytes salt");
        console2.logBytes(abi.encodePacked(salt));
        vm.writeFileBinary(fileName, abi.encodePacked(salt));
    }

    function run() external {
        bool testnet = vm.envBool("TEST");
        console2.log("test: ", testnet ? 1 : 0);
        bytes memory configBytes = _getConfigJson({mainnet: !testnet, layer1: true});
        Base.L1Config memory config = abi.decode(configBytes, (Base.L1Config));
        console2.log("config usdc: ", config.usdc);

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

        vm.stopBroadcast();
    }
}
