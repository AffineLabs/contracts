// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { DSTestPlus } from "./TestPlus.sol";
import { stdStorage, StdStorage } from "forge-std/src/stdlib.sol";
import { Deploy } from "./Deploy.sol";

import { L1Vault } from "../ethereum/L1Vault.sol";
import { ICToken } from "../interfaces/compound/ICToken.sol";
import { IComptroller } from "../interfaces/compound/IComptroller.sol";
import { L1CompoundStrategy } from "../ethereum/L1CompoundStrategy.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";

contract L1CompoundStratTestFork is DSTestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C);

    L1Vault vault;
    L1CompoundStrategy strategy;

    // constants
    uint256 usdcBalancesStorageSlot = 0;
    uint256 oneUSDC = 1e6;
    uint256 halfUSDC = oneUSDC / 2;

    function setUp() public {
        vault = Deploy.deployL1Vault();

        // make vault token equal to the L1 (Goerli) usdc address
        uint256 slot = stdstore.target(address(vault)).sig("token()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(usdc))));
        cheats.store(address(vault), bytes32(slot), tokenAddr);

        strategy = new L1CompoundStrategy(
            vault,
            ICToken(0xCEC4a43eBB02f9B80916F1c718338169d6d5C1F0), // cToken
            IComptroller(0x627EA49279FD0dE89186A58b8758aD02B6Be2867), // Comptroller
            IUniLikeSwapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D), // sushiswap router on goerli
            0xe16C7165C8FeA64069802aE4c4c9C320783f2b6e, // reward token -> comp token
            0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6 // wrapped eth address
        );
    }

    function testStrategyInvest() public {
        // Give the Vault 1 usdc
        uint256 slot = stdstore.target(address(usdc)).sig(usdc.balanceOf.selector).with_key(address(vault)).find();
        cheats.store(address(usdc), bytes32(slot), bytes32(uint256(1e6)));

        vault.addStrategy(strategy, 5000);
        cheats.prank(address(0)); // staging address is 0 in the default vault
        vault.afterReceive();

        // Strategy deposits all of usdc into Compound
        assertInRange(strategy.cToken().balanceOfUnderlying(address(strategy)), halfUSDC - 1, halfUSDC);
    }
}
