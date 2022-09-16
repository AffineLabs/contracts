// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L1Vault} from "../ethereum/L1Vault.sol";
import {CurveStrategy} from "../ethereum/CurveStrategy.sol";
import {I3CrvMetaPoolZap} from "../interfaces/IMetaPoolZap.sol";

contract CurveStratTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    L1Vault vault;
    CurveStrategy strategy;

    function setUp() public {
        vm.createSelectFork("ethereum", 14_971_385);
        vault = deployL1Vault();

        // make vault token equal to the L1 usdc address
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("asset()").find()),
            bytes32(uint256(uint160(address(usdc))))
        );

        strategy =
        new CurveStrategy(vault, ERC20(0x5a6A4D54456819380173272A5E8E9B9904BdF41B), I3CrvMetaPoolZap(0xA79828DF1850E8a3A3064576f380D90aECDD3359));
    }

    function testCanMintLpTokens() public {
        // get some usdc
        // invest in the vault
        deal(address(usdc), address(this), 1e6);

        usdc.approve(address(strategy), type(uint256).max);
        strategy.invest(1e6);

        assertGt(ERC20(strategy.metaPool()).balanceOf(address(strategy)), 0);
        emit log_named_uint("strat tvl: ", strategy.totalLockedValue());
        assertApproxEqRel(strategy.totalLockedValue(), 1e6, 1e18);
    }

    function testCanDivest() public {
        // One lp token is worth more than a dollar
        deal(address(strategy.metaPool()), address(strategy), 1e18);

        vm.prank(address(vault));
        uint256 amountDivested = strategy.divest(1e6);

        assertTrue(amountDivested == 1e6);
        assertTrue(usdc.balanceOf(address(vault)) == 1e6);
    }
}
