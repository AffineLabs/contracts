// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {ConvexUSDCStrategy} from "../ethereum/ConvexUSDCStrategy.sol";
import {IUSDCMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";
import {IConvexBooster} from "../interfaces/convex/IConvexBooster.sol";
import {IConvexClaimZap} from "../interfaces/convex/IConvexClaimZap.sol";
import {IConvexCrvRewards} from "../interfaces/convex/IConvexCrvRewards.sol";
import {IUniLikeSwapRouter} from "../interfaces/IUniLikeSwapRouter.sol";

contract CurveStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    L1Vault vault;
    ConvexUSDCStrategy strategy;

    function setUp() public {
        vm.createSelectFork("ethereum", 15_624_364);
        vault = deployL1Vault();

        // make vault token equal to the L1 usdc address
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(usdc))))
        );
        strategy = new ConvexUSDCStrategy(
            vault, 
            IUSDCMetaPoolZap(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2),
            100,
            IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31),
            IConvexClaimZap(0xDd49A93FDcae579AE50B4b9923325e9e335ec82B),
            IConvexCrvRewards(0x7e880867363A7e321f5d260Cade2B0Bb2F717B02),
            IUniLikeSwapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)
        );
    }

    function testCanDeposit() public {
        // get some usdc
        // invest in the vault
        deal(address(usdc), address(this), 1e6);
        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(1e6);

        emit log_named_uint("strat tvl: ", strategy.totalLockedValue());
        assertApproxEqRel(strategy.totalLockedValue(), 1e6, 1e18);
    }

    function testCanDivest() public {
        // One lp token is worth more than a dollar
        deal(address(usdc), address(this), 1e6);
        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(1e6);

        vm.prank(address(vault));
        strategy.divest(1e6);
        emit log_named_uint("vault usdc: ", usdc.balanceOf(address(vault)));
        assert(usdc.balanceOf(address(vault)) == 1e6);
    }
}
