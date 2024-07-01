// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LevMaticXLoopStrategy, AffineVault, FixedPointMathLib} from "src/strategies/LevMaticXLoopStrategy.sol";
import {EigenDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/EigenDelegator.sol";
import {IStEth} from "src/interfaces/lido/IStEth.sol";
import {UltraLRT} from "src/vaults/restaking/UltraLRT.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {
    WithdrawalInfo,
    QueuedWithdrawalParams,
    ApproverSignatureAndExpiryParams,
    IDelegationManager,
    IStrategyManager,
    IStrategy
} from "src/interfaces/eigenlayer/eigen.sol";

//TODO: Add tests for external withdrawal records and completion

contract EigenDelegatorTest is TestPlus {
    uint256 init_assets = 10e18; // 10 stETH
    address vault;
    EigenDelegator delegator;
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;

    /// @notice StrategyManager for Eigenlayer
    IStrategyManager public constant STRATEGY_MANAGER = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    /// @notice DelegationManager for Eigenlayer
    IDelegationManager public constant DELEGATION_MANAGER =
        IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    /// @notice stETH strategy on Eigenlayer
    IStrategy public constant STAKED_ETH_STRATEGY = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

    event OperatorSharesIncreased(address indexed operator, address staker, address strategy, uint256 shares);

    receive() external payable {}

    ERC20 public asset = ERC20((0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)); // stETH

    function setUp() public {
        // fork eth
        vm.createSelectFork("ethereum", 19_771_000);

        UltraLRT tmpVault = new UltraLRT();

        EigenDelegator delImpl = new EigenDelegator();

        DelegatorBeacon beacon = new DelegatorBeacon(address(delImpl), governance);

        tmpVault.initialize(governance, address(asset), address(beacon), "uLRT", "uLRT");
        alice = address(tmpVault);
        delegator = new EigenDelegator();
        delegator.initialize(alice, operator);
    }

    function _getAsset(address to, uint256 amount) internal returns (uint256) {
        deal(to, amount);
        vm.prank(to);
        IStEth(address(asset)).submit{value: amount}(address(0));
        return asset.balanceOf(to);
    }

    function testDelegate() public {
        // deal(address(asset), alice, init_assets);
        uint256 stEthAmount = _getAsset(alice, init_assets);
        IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vm.startPrank(alice);

        // // delegate
        asset.approve(address(delegator), stEthAmount);
        delegator.delegate(stEthAmount);
        // uint256 sharesAmount = stEthStrategy.underlyingToShares(stEthAmount);
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(stEthAmount), stEthStrategy.shares(address(delegator)));
        // // request withdrawal
        delegator.requestWithdrawal(stEthAmount);
        uint256 blockNum = block.number;
        // console2.log("====> %s", delegator.totalLockedValue());
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });

        vm.startPrank(governance);
        delegator.completeWithdrawalRequest(params);

        vm.startPrank(alice);
        delegator.withdraw();

        assertApproxEqAbs(delegator.totalLockedValue(), 0, 10);
        assertApproxEqAbs(asset.balanceOf(alice), stEthAmount, 10);
    }

    function testWithdrawalWithInvalidData() public {
        // deal(address(asset), alice, init_assets);
        uint256 stEthAmount = _getAsset(alice, init_assets);
        IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vm.startPrank(alice);

        // // delegate
        asset.approve(address(delegator), stEthAmount);
        delegator.delegate(stEthAmount);
        // uint256 sharesAmount = stEthStrategy.underlyingToShares(stEthAmount);
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(stEthAmount), stEthStrategy.shares(address(delegator)));
        // // request withdrawal
        delegator.requestWithdrawal(stEthAmount);
        uint256 blockNum = block.number;
        // console2.log("====> %s", delegator.totalLockedValue());
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 1, // invalid nonce
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });

        // invalid length of params
        WithdrawalInfo[] memory invalidLenParam = new WithdrawalInfo[](2);
        vm.expectRevert();
        delegator.completeWithdrawalRequest(invalidLenParam);
        // invalid nonce
        vm.expectRevert();
        delegator.completeWithdrawalRequest(params);

        params[0].nonce = 0;
        vm.startPrank(governance);
        delegator.completeWithdrawalRequest(params);

        vm.startPrank(alice);
        delegator.withdraw();

        assertApproxEqAbs(delegator.totalLockedValue(), 0, 10);
        assertApproxEqAbs(asset.balanceOf(alice), stEthAmount, 10);
    }

    function _doExternalWithdrawRequest(uint256 assets) internal returns (bytes32 root) {
        vm.startPrank(address(delegator));

        QueuedWithdrawalParams[] memory params = new QueuedWithdrawalParams[](1);

        uint256[] memory shares = new uint256[](1);
        shares[0] =
            Math.min(STAKED_ETH_STRATEGY.underlyingToShares(assets), STAKED_ETH_STRATEGY.shares(address(delegator)));

        // in any case if converted shares is zero will revert the ops.
        if (shares[0] > 0) {
            address[] memory strategies = new address[](1);
            strategies[0] = address(STAKED_ETH_STRATEGY);
            params[0] = QueuedWithdrawalParams(strategies, shares, address(delegator));

            bytes32[] memory withdrawalRoots = DELEGATION_MANAGER.queueWithdrawals(params);
            return withdrawalRoots[0];
        }
    }

    function testExternalWithdrawal() public {
        // deal(address(asset), alice, init_assets);
        uint256 stEthAmount = _getAsset(alice, init_assets);
        IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vm.startPrank(alice);

        // // delegate
        asset.approve(address(delegator), stEthAmount);
        delegator.delegate(stEthAmount);
        // uint256 sharesAmount = stEthStrategy.underlyingToShares(stEthAmount);
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(stEthAmount), stEthStrategy.shares(address(delegator)));
        // // request withdrawal

        _doExternalWithdrawRequest(stEthAmount);

        uint256 blockNum = block.number;
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });
        vm.stopPrank();
        // invalid length of params
        WithdrawalInfo[] memory invalidLenParam = new WithdrawalInfo[](2);
        vm.expectRevert();
        delegator.completeWithdrawalRequest(invalidLenParam);

        // not recorded withdrawal
        vm.expectRevert();
        delegator.completeWithdrawalRequest(params);

        // record withdrawal request
        // not a harvester
        vm.expectRevert();
        delegator.recordWithdrawalsRequest(params[0]);

        // invalid withdrawer
        params[0].withdrawer = (address(0));
        params[0].staker = address(0);
        vm.expectRevert();
        delegator.recordWithdrawalsRequest(params[0]);
        params[0].withdrawer = address(delegator);
        params[0].staker = address(delegator);

        // record invalid nonce request
        params[0].nonce = 1;
        vm.prank(governance);
        vm.expectRevert();
        delegator.recordWithdrawalsRequest(params[0]);
        params[0].nonce = 0;

        // record withdrawal request
        vm.prank(governance);
        delegator.recordWithdrawalsRequest(params[0]);

        // try recording again
        vm.prank(governance);
        vm.expectRevert();
        delegator.recordWithdrawalsRequest(params[0]);

        // complete withdraw
        vm.startPrank(governance);
        delegator.completeWithdrawalRequest(params);

        vm.startPrank(alice);
        delegator.withdraw();

        assertApproxEqAbs(delegator.totalLockedValue(), 0, 10);
        assertApproxEqAbs(asset.balanceOf(alice), stEthAmount, 10);
    }

    function testZeroShareWithdrawal() public {
        // deal(address(asset), alice, init_assets);
        uint256 stEthAmount = _getAsset(alice, init_assets);
        // IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vm.startPrank(alice);

        // // delegate
        asset.approve(address(delegator), stEthAmount);
        delegator.delegate(stEthAmount);
        // uint256 sharesAmount = stEthStrategy.underlyingToShares(stEthAmount);
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        // // request withdrawal for zero assets
        delegator.requestWithdrawal(0);
    }

    function testReDelegation() public {
        // deal(address(asset), alice, init_assets);
        uint256 stEthAmount = _getAsset(alice, init_assets);
        IStrategy stEthStrategy = IStrategy(0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        vm.startPrank(alice);

        // // delegate
        asset.approve(address(delegator), stEthAmount);
        delegator.delegate(stEthAmount);
        // uint256 sharesAmount = stEthStrategy.underlyingToShares(stEthAmount);
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        assertApproxEqAbs(asset.balanceOf(alice), 0, 10);

        uint256 withdrawableStEthShares =
            Math.min(stEthStrategy.underlyingToShares(stEthAmount), stEthStrategy.shares(address(delegator)));
        // // request withdrawal
        delegator.requestWithdrawal(stEthAmount);
        uint256 blockNum = block.number;
        // console2.log("====> %s", delegator.totalLockedValue());
        assertApproxEqAbs(delegator.totalLockedValue(), stEthAmount, 10);
        vm.roll(block.number + 1_000_000);

        // complete withdrawal
        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawableStEthShares;
        address[] memory strategies = new address[](1);
        strategies[0] = address(stEthStrategy);

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: operator,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });

        vm.startPrank(governance);
        delegator.completeWithdrawalRequest(params);

        vm.startPrank(alice);
        delegator.withdraw();

        assertApproxEqAbs(delegator.totalLockedValue(), 0, 10);
        assertApproxEqAbs(asset.balanceOf(alice), stEthAmount, 10);
        assertTrue(true);

        vm.recordLogs();

        asset.approve(address(delegator), asset.balanceOf(alice));
        delegator.delegate(asset.balanceOf(alice));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool opsShareIncreased;
        for (uint256 i = 0; i < entries.length; i++) {
            if (OperatorSharesIncreased.selector == entries[i].topics[0]) {
                opsShareIncreased = true;
                break;
            }
        }
        assertTrue(opsShareIncreased);
    }
}
