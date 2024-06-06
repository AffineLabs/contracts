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

contract EigenDelegatorTest is TestPlus {
    uint256 init_assets = 10e18; // 10 stETH
    address vault;
    EigenDelegator delegator;
    address operator = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;

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
        assertTrue(true);
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
