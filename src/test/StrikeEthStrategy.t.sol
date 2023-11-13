// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {StrikeEthStrategy, ICToken, AffineVault, FixedPointMathLib} from "src/strategies/StrikeEthStrategy.sol";
import {VaultV2} from "src/vaults/VaultV2.sol";

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

    function _getVault() internal virtual returns (AffineVault) {
        return AffineVault(address(deployL1Vault()));
    }

    function setUp() public {
        vm.createSelectFork("ethereum", 18_544_000);

        address[] memory strategists = new address[](1);
        strategists[0] = address(this);
        vault = _getVault();

        staking = new MockStrikeEthStrategy(vault, ICToken(0xbEe9Cf658702527b0AcB2719c1FAA29EdC006a92), strategists);
        vm.prank(governance);
        vault.addStrategy(staking, 10_000);
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

contract StrikeEthStrategyVaultTest is StrikeEthStrategyTest {
    ERC20 public asset = ERC20((0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 public init_assets;
    VaultV2 v2_vault;

    function _getVault() internal virtual override returns (AffineVault) {
        init_assets = 10 * (10 ** asset.decimals());
        v2_vault = new VaultV2();
        v2_vault.initialize(governance, address(asset), "TV", "TV");
        return AffineVault(address(v2_vault));
    }

    function _giveWethToAlice() internal {
        deal(address(asset), alice, init_assets);
    }

    function testDepositWithdraw() public {
        _giveWethToAlice();
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        v2_vault.deposit(init_assets, alice);

        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.01e18);
        vm.startPrank(governance);

        v2_vault.depositIntoStrategies(init_assets);

        assertApproxEqRel(vault.vaultTVL(), init_assets, 0.01e18);

        assertApproxEqAbs(staking.totalLockedValue(), init_assets, 0.01e18);

        assertEq(asset.balanceOf(address(alice)), 0);

        vm.startPrank(alice);
        v2_vault.withdraw(init_assets, alice, alice);

        assertApproxEqRel(asset.balanceOf(alice), init_assets, 0.01e18);
    }
}
