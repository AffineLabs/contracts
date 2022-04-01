// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";

import { L1Vault } from "../ethereum/L1Vault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { IExchangeRateFeeder } from "../interfaces/anchor/IExchangeRateFeeder.sol";
import { IConversionPool } from "../interfaces/anchor/IConversionPool.sol";
import { L1AnchorStrategy } from "../ethereum/L1AnchorStrategy.sol";

contract EthAnchorStratTestFork is DSTestPlus {
    using stdStorage for StdStorage;
    ERC20 usdc = ERC20(0xE015FD30cCe08Bc10344D934bdb2292B1eC4BBBD);

    L1Vault vault;
    L1AnchorStrategy strategy;

    // constants
    uint256 hundredUSDC = 100e6;

    function setUp() public {
        vault = Deploy.deployL1Vault();
        // make vault token equal to the L1 (ropsten) usdc address
        uint256 slot = stdstore.target(address(vault)).sig("token()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        cheats.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1AnchorStrategy(
            vault,
            IERC20(0xFff8fb0C13314c90805a808F48c7DFF37e95Eb16),
            IConversionPool(0x92E68C8C24a0267fa962470618d2ffd21f9b6a95),
            IExchangeRateFeeder(0x79E0d9bD65196Ead00EE75aB78733B8489E8C1fA)
        );
    }

    function testStrategyInvest() public {
        // Give the Vault 100 usdc
        uint256 slot = stdstore.target(address(usdc)).sig(usdc.balanceOf.selector).with_key(address(vault)).find();
        cheats.store(address(usdc), bytes32(slot), bytes32(hundredUSDC));
        vault.addStrategy(strategy, 5_000);

        // Make sure strategy deposits fifty USDC to Eth Anchor after receiving money from the vault
        bytes memory expectedData = abi.encodeWithSignature("deposit(uint256)", hundredUSDC / 2);
        cheats.expectCall(address(strategy.usdcConversionPool()), expectedData);

        // vault will invest in strategy after receiving money from staging
        cheats.prank(address(0)); // staging address is 0 in the default vault
        vault.afterReceive();

        assertEq(usdc.balanceOf(address(vault)), hundredUSDC / 2);
    }
}
