// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StrikeEthStrategy, ICToken, AffineVault, FixedPointMathLib} from "src/strategies/StrikeEthStrategy.sol";

import {console2} from "forge-std/console2.sol";

contract MockStrikeEthStrategy is StrikeEthStrategy {
    constructor(AffineVault _vault, ICToken _cToken, address[] memory strategists)
        StrikeEthStrategy(_vault, _cToken, strategists)
    {}

    function addToPosition(uint256 amount) external {
        _afterInvest(amount);
    }

    function collateral() external returns (uint256) {
        return cToken.balanceOfUnderlying(address(this));
    }

    function debt() external returns (uint256) {
        return cToken.borrowBalanceCurrent(address(this));
    }
}

contract StrikeEthStrategyTest is TestPlus {
    using FixedPointMathLib for uint256;

    MockStrikeEthStrategy staking;
    AffineVault vault;

    uint256 depSize = 10 ether;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum", 18_544_000);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = AffineVault(address(deployL1Vault()));

        staking = new MockStrikeEthStrategy(vault, ICToken(0xbEe9Cf658702527b0AcB2719c1FAA29EdC006a92), strategists);
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
        _giveEther(depSize);
        staking.addToPosition(depSize);
    }

    function testLeverage() public {
        testAddToPosition();
        uint256 collateral = staking.collateral();
        assertApproxEqRel(collateral, (depSize * 10_000) / (10_000 - staking.borrowBps()), 0.02e18);
    }

    function testClosePosition() public {
        testAddToPosition();
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        assertApproxEqRel(staking.totalLockedValue(), depSize, 0.01e18);
        _divest(1 ether);
        assertApproxEqRel(staking.totalLockedValue(), depSize - 1 ether, 0.01e18);
        console2.log("TVL : %s", staking.totalLockedValue());
    }

    function testTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console2.log("TVL:  %s", tvl);
        assertApproxEqRel(tvl, depSize, 0.01e18);
    }

    function testMutateTotalLockedValue() public {
        testAddToPosition();
        uint256 tvl = staking.totalLockedValue();
        console2.log("Orig tvl: ", tvl);
        console2.log("orig collateral: ", staking.collateral());
        console2.log("orig debt: ", staking.debt());

        vm.prank(address(vault));
        staking.divest(1 ether);

        assertApproxEqRel(staking.totalLockedValue(), tvl - 1 ether, 0.01e18);

        console2.log("Orig tvl: ", staking.totalLockedValue());
        console2.log("orig collateral: ", staking.collateral());
        console2.log("orig debt: ", staking.debt());
    }

    function testSetBorrowBps() public {
        staking.setBorrowBps(10_000);
        assertEq(staking.borrowBps(), 10_000);
    }

    function testRebalanceWithNewLev() public {
        testAddToPosition();
        _testLev(4000);
        _testLev(7000);
        _testLev(6000);
        _testLev(3000);
        _testLev(6000);
    }

    function testFullDivest() public {
        testAddToPosition();
        console2.log("TVL ", staking.totalLockedValue());
        vm.prank(address(vault));
        staking.divest(depSize);
    }

    function _testLev(uint256 borrowBps) internal {
        uint256 col;
        uint256 deb;
        uint256 r;
        staking.setBorrowBps(borrowBps);

        staking.rebalance();

        (col, deb) = staking.getCollateralAndDebt();
        r = ((deb * 10_000) / col);
        assertApproxEqAbs(r, staking.borrowBps(), 100);
        assertApproxEqRel(staking.totalLockedValue(), depSize, 0.01e18);

        console2.log("debt ratio ", r);
        console2.log("debt ", deb);
        console2.log("col ", col);
    }
}
