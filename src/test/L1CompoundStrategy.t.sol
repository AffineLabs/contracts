// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { DSTestPlus } from "./TestPlus.sol";
import { IHevm } from "./IHevm.sol";
import { Deploy } from "./Deploy.sol";

import { L1Vault } from "../ethereum/L1Vault.sol";
import { ICToken } from "../interfaces/compound/ICToken.sol";
import { IComptroller } from "../interfaces/compound/IComptroller.sol";
import { L1CompoundStrategy } from "../ethereum/L1CompoundStrategy.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";

contract L1CompoundStratTestFork is DSTestPlus {
    ERC20 usdc = ERC20(0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C);

    L1Vault vault;
    L1CompoundStrategy strategy;

    // constants
    uint256 usdcBalancesStorageSlot = 0;
    uint256 oneUSDC = 1e6;
    uint256 halfUSDC = oneUSDC / 2;

    // 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D is a cheat address of hevm which allows manipulating time
    // See https://github.com/dapphub/dapptools/pull/71
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        vault = Deploy.deployL1Vault();
        strategy = new L1CompoundStrategy(
            vault,
            ICToken(0xCEC4a43eBB02f9B80916F1c718338169d6d5C1F0), // cToken
            IComptroller(0x627EA49279FD0dE89186A58b8758aD02B6Be2867), // Comptroller
            IUniLikeSwapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D), // sushiswap router on goerli
            0xe16C7165C8FeA64069802aE4c4c9C320783f2b6e, // reward token -> comp token
            0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6 // wrapped eth address
        );
    }

    function testStrategyHarvestSuccessfully() public {
        // Give the Vault 1 usdc
        hevm.store(address(usdc), keccak256(abi.encode(address(vault), usdcBalancesStorageSlot)), bytes32(oneUSDC));

        vault.addStrategy(strategy);
        vault.depositIntoStrategy(strategy, halfUSDC);

        // Strategy deposits all of usdc into Compound
        assertInRange(strategy.cToken().balanceOfUnderlying(address(strategy)), halfUSDC - 1, halfUSDC);
    }

    // TODO: Add more unit tests.
}
