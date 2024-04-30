// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LevMaticXLoopStrategy, AffineVault, FixedPointMathLib} from "src/strategies/LevMaticXLoopStrategy.sol";
import {AffineDelegator, WithdrawalInfo, IStrategy} from "src/vaults/restaking/AffineDelegator.sol";

import {console2} from "forge-std/console2.sol";

contract AffineDelegatorTest is TestPlus {
    uint256 init_assets = 10e18; // 10 stETH
    address vault;
    AffineDelegator delegator;

    receive() external payable {}

    ERC20 public asset = ERC20((0xae78736Cd615f374D3085123A210448E74Fc6393)); // rocket pool stETH


    function setUp() public {
        // fork eth
        vm.createSelectFork("ethereum");
        vault = alice;

        AffineDelegator impl = new AffineDelegator();

        bytes memory initData = abi.encodeCall(AffineDelegator.initialize, (governance, vault));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        delegator = AffineDelegator(address(proxy));
    }

    function testDelegate() public {
        deal(address(asset), alice, init_assets);
        IStrategy stEthStrategy = IStrategy(0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2);
        vm.startPrank(alice);
        asset.approve(address(delegator), init_assets);
        delegator.delegate(init_assets);
        assertEq(delegator.totalLockedValue(), init_assets);
        assertEq(asset.balanceOf(alice), 0);
        // vm.roll(block.number + 10000);
        delegator.requestWithdrawal(init_assets);

        // record block num into a var
        uint256 blockNum = block.number;
        assertEq(delegator.totalLockedValue(), init_assets);
        vm.roll(block.number + 1000000);

        WithdrawalInfo[] memory params = new WithdrawalInfo[](1);
        uint256 sharesx = stEthStrategy.underlyingToShares(init_assets);
        uint256[] memory shares = new uint256[](1);
        shares[0] = sharesx;
        // shares[0] = 1;
        address[] memory strategies = new address[](1);
        strategies[0] = 0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2;

        params[0] = WithdrawalInfo({
            staker: address(delegator),
            delegatedTo: 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5,
            withdrawer: address(delegator),
            nonce: 0,
            startBlock: uint32(blockNum),
            strategies: strategies,
            shares: shares
        });
        
        delegator.completeWithdrawalRequest(params);
        delegator.withdraw();

        assertApproxEqAbs(delegator.totalLockedValue(), 0, 10);
        assertApproxEqAbs(asset.balanceOf(alice), init_assets, 10);
    }

}
