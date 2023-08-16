// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {
    LidoLev,
    IBalancerVault,
    IFlashLoanRecipient,
    AffineVault,
    ICdpManager,
    ISwapRouter,
    FixedPointMathLib
} from "src/strategies/LidoLev.sol";

import {console} from "forge-std/console.sol";

contract MockLidoLev is LidoLev {
    constructor(LidoLev oldStrat, uint256 _leverage, AffineVault _vault, address[] memory strategists)
        LidoLev(oldStrat, _leverage, _vault, strategists)
    {}

    function daiToEth(uint256 dai) external view returns (uint256) {
        return _daiToEth(dai, _getDaiPrice());
    }

    function getDivestAmounts(uint256 wethToDivest) external returns (uint256 daiToBorrow) {
        (, daiToBorrow) = _getDivestFlashLoanAmounts(wethToDivest);
    }
}

contract LidoLevTest is TestPlus {
    using FixedPointMathLib for uint256;

    MockLidoLev staking;
    AffineVault vault;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum", 17_687_253);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new MockLidoLev(LidoLev(payable(address(0))), 175, vault, strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 0);
    }

    function _giveEther(uint256 amount) internal {
        ERC20 weth = staking.WETH();
        deal(address(weth), address(staking), amount);
    }

    function _divest(uint256 amount) internal {
        vm.prank(address(vault));
        staking.divest(amount);
    }

    function testAddToPosition() public {
        _giveEther(30 ether);
        staking.addToPosition(30 ether);
    }

    function testLeverage() public {
        testAddToPosition();
        (uint256 wstEthCollat,) = staking.VAT().urns(staking.ILK(), staking.urn());

        uint256 makerCollateral = staking.WSTETH().getStETHByWstETH(wstEthCollat);
        uint256 depSize = 30 ether;
        assertApproxEqRel(makerCollateral, depSize * 175 / 100, 0.0001e18);
    }

    function testClosePosition() public {
        ERC20 weth = staking.WETH();
        testAddToPosition();
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        _divest(1 ether);
        console.log("WETH balance: %s", weth.balanceOf(address(this)));
        console.log("WETH staking balance: %s", weth.balanceOf(address(staking)));
    }

    function testTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 30 ether, 0.001e18);
    }

    function testTotalLockedValueII() public {
        _giveEther(7 ether);
        staking.addToPosition(7 ether);
        uint256 tvl = staking.totalLockedValue();
        console.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, 7 ether, 0.001e18);
    }

    function testMutateTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();

        deal(address(staking.WETH()), address(this), 1 ether);
        staking.WETH().transfer(address(staking), 1 ether);

        assertApproxEqRel(staking.totalLockedValue(), tvl + 1 ether, 0.001e18);

        vm.prank(address(vault));
        staking.divest(1 ether);
        assertApproxEqRel(staking.totalLockedValue(), tvl, 0.001e18);
    }

    /// @dev Test divergence between maker debt and comp collateral
    function testSecondFlashLoan() public {
        testAddToPosition();

        uint256 compDai = staking.CDAI().balanceOfUnderlying(address(staking));
        uint256 makerDai = (compDai * 101) / 100; // Maker debt is 1% higher than Compound collateral

        // Calls to maker will now return the inflated debt of `makerDai`
        ICdpManager maker = staking.MAKER();
        address urn = maker.urns(staking.cdpId());
        (uint256 wstCollat,) = staking.VAT().urns(staking.ILK(), urn);

        vm.mockCall(
            address(staking.VAT()),
            abi.encodeCall(staking.VAT().urns, (staking.ILK(), urn)),
            abi.encode(wstCollat, makerDai)
        );

        // This number should be roughly 60 DAI, since we have about $100k in wsteth collateral (30 * 1.75 * 2k)
        // and about 60k (~58%) in maker debt. We increase this by ~$600 via the mock above. We are divesting about 10% of the vault
        // So we will need to flashloan an extra $60 to cover the gap between the maker debt and comp collateral.
        uint256 daiBorrowed = staking.getDivestAmounts(3 ether);

        // Expect call on the uniswap router
        ISwapRouter.ExactInputSingleParams memory uniParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(staking.WETH()),
            tokenOut: address(staking.DAI()),
            fee: 500,
            recipient: address(staking),
            deadline: block.timestamp,
            amountIn: staking.daiToEth(daiBorrowed).mulDivUp(110, 100),
            amountOutMinimum: daiBorrowed,
            sqrtPriceLimitX96: 0
        });
        vm.expectCall(address(staking.UNI_ROUTER()), abi.encodeCall(ISwapRouter.exactInputSingle, (uniParams)));

        // Divest 3 ether
        _divest(3 ether);
    }

    /// @dev Rebalance scenario #1
    function testBorrowMoreEth() public {
        testAddToPosition();

        uint256 oldTvl = staking.totalLockedValue();
        uint256 oldCompDebt = staking.CETH().borrowBalanceCurrent(address(staking));
        staking.rebalance(1 ether, 0);

        assertEq(staking.CETH().borrowBalanceCurrent(address(staking)), oldCompDebt + 1 ether);
        assertEq(staking.totalLockedValue(), oldTvl);
    }

    /// @dev Rebalance scenario #2
    function testBorrowMoreDai() public {
        testAddToPosition();

        uint256 oldTvl = staking.totalLockedValue();
        (, uint256 oldMakerDebt) = staking.VAT().urns(staking.ILK(), staking.urn());
        staking.rebalance(0, 1 ether);

        (, uint256 newMakerDebt) = staking.VAT().urns(staking.ILK(), staking.urn());
        assertEq(newMakerDebt, oldMakerDebt + 1 ether);
        // We borrow 1 ether of Dai but compound will round against us when depositing collateral
        assertApproxEqRel(staking.totalLockedValue(), oldTvl, 0.0001e18);
    }

    function testMinDepositAmt() public {
        _giveEther(10 ether);
        vm.expectRevert();
        staking.addToPosition(1 ether);

        staking.addToPosition(7 ether);
    }

    function testUpgrade() public {
        testAddToPosition();
        uint256 beforeTvl = staking.totalLockedValue();

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        LidoLev staking2 = new LidoLev(staking, 175, vault, strategists);
        assertEq(staking2.totalLockedValue(), 0);

        vm.prank(governance);
        staking.upgrade(address(staking2));

        // Cdp was transferred
        assertEq(staking.cdpId(), staking2.cdpId());
        assertEq(staking.urn(), staking2.urn());

        // All value was moved to staking2
        assertEq(staking.totalLockedValue(), 0);
        assertEq(staking2.totalLockedValue(), beforeTvl);

        // We can divest in staking2
        vm.prank(address(vault));
        staking2.divest(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), 29 ether, 0.001e18);

        // We can invest in staking2
        // Dealing to staking2 directly will overwrite any weth dust and slighlty reduce the tvl
        deal(address(staking2.WETH()), address(this), 1 ether);
        ERC20(staking2.WETH()).transfer(address(staking2), 1 ether);
        staking2.addToPosition(1 ether);
        assertApproxEqRel(staking2.totalLockedValue(), 30 ether, 0.001e18);
    }
}
