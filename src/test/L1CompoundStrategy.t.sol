// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { DSTestPlus } from "./TestPlus.sol";
import { IHevm } from "./IHevm.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

import { L1Vault } from "../ethereum/L1Vault.sol";
import { Create2Deployer } from "./Create2Deployer.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { IRootChainManager } from "../interfaces/IRootChainManager.sol";
import { ICToken } from "../interfaces/compound/ICToken.sol";
import { IComptroller } from "../interfaces/compound/IComptroller.sol";
import { L1CompoundStrategy } from "../ethereum/L1CompoundStrategy.sol";
import { IUniLikeSwapRouter } from "../interfaces/IUniLikeSwapRouter.sol";
import { BaseStrategy as Strategy } from "../BaseStrategy.sol";

// contract L1CompoundStratTestFork is DSTestPlus {
//     ERC20 compToken = ERC20(0xe16C7165C8FeA64069802aE4c4c9C320783f2b6e);
//     IComptroller comptroller = IComptroller(0x627EA49279FD0dE89186A58b8758aD02B6Be2867);
//     ICToken cusdc = ICToken(0xCEC4a43eBB02f9B80916F1c718338169d6d5C1F0);
//     ERC20 usdc = ERC20(0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C);
//     // 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D is a cheat address of hevm which allows manipulating time
//     // See https://github.com/dapphub/dapptools/pull/71
//     IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//     IWormhole wormhole = IWormhole(0x706abc4E45D419950511e474C7B9Ed348A4a716c);
//     ERC20 weth = ERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
//     IUniLikeSwapRouter uniswapRouter = IUniLikeSwapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
//     // `rootChainManager` is not used in this test. Real address: 0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74;
//     IRootChainManager rootChainManager = IRootChainManager(address(0));
//     // `erc20Predicate` is not used in this test. Real address: 0xdD6596F2029e6233DEFfaCa316e6A95217d4Dc34;
//     address erc20Predicate = address(0);
//     uint256 usdcBalancesStorageSlot = 0;

//     L1Vault vault;
//     Create2Deployer create2Deployer;
//     L1CompoundStrategy strategy;

//     // constants
//     uint256 oneUSDC = 1e6;
//     uint256 halfUSDC = oneUSDC / 2;

//     function setUp() public {
//         create2Deployer = new Create2Deployer();
//         vault = new L1Vault();
//         vault.initialize(
//             address(this), // governance
//             usdc, // token -> Goerli USDC that Compund takes in
//             wormhole, // wormhole
//             create2Deployer, // create2deployer (needs to be a real contract)
//             rootChainManager, // Polygon root chain manager
//             erc20Predicate // Polygon ERC20 predicate
//         );
//         strategy = new L1CompoundStrategy(
//             address(vault),
//             cusdc, // aave adress provider registry
//             comptroller, // dummy incentives controller
//             uniswapRouter, // sushiswap router on goerli
//             address(compToken), // reward token -> comp token
//             address(weth) // wrapped eth address
//         );
//     }

//     function testStrategyHarvestSuccessfully() public {
//         // Give the Vault 1 usdc
//         hevm.store(address(usdc), keccak256(abi.encode(address(vault), usdcBalancesStorageSlot)), bytes32(oneUSDC));

//         // This contract is the governance address so this will work
//         vault.addStrategy(Strategy(address(strategy)), 5000, 0, type(uint256).max);

//         strategy.harvest();

//         // After calling harvest for the first time, we take 5000/10000 percentage of the vaults assets
//         assertEq(usdc.balanceOf(address(vault)), halfUSDC);
//         assertEq(vault.totalDebt(), halfUSDC);

//         // Strategy deposits all of usdc into Compound
//         assertInRange(strategy.cToken().balanceOfUnderlying(address(strategy)), halfUSDC - 1, halfUSDC);

//         (, , , , , uint256 totalDebt, , ) = vault.strategies(Strategy(address(strategy)));
//         assertEq(totalDebt, halfUSDC);
//     }

//     // TODO: Add more unit tests.
// }
