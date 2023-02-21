// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

import {SmartWallet} from "src/both/SmartWallet.sol";

contract SmartWalletTest is TestPlus {
    MockERC20 asset1;
    MockERC20 asset2;
    SmartWallet wallet;

    function setUp() public {
        asset1 = new MockERC20("Mock", "MT", 6);
        asset2 = new MockERC20("Mock", "MT", 6);

        wallet = new SmartWallet(address(this));

        asset1.mint(address(wallet), 10);
        asset2.mint(address(wallet), 20);
    }

    function testMultiCall() public {
        SmartWallet.Call memory call1 =
            SmartWallet.Call({target: address(asset1), callData: abi.encodeCall(asset1.transfer, (address(0), 10))});
        SmartWallet.Call memory call2 =
            SmartWallet.Call({target: address(asset2), callData: abi.encodeCall(asset2.transfer, (address(0), 20))});

        SmartWallet.Call[] memory calls = new SmartWallet.Call[](2);
        calls[0] = call1;
        calls[1] = call2;
        wallet.aggregate(calls);

        assertEq(asset1.balanceOf(address(wallet)), 0);
        assertEq(asset1.balanceOf(address(0)), 10);

        assertEq(asset2.balanceOf(address(wallet)), 0);
        assertEq(asset2.balanceOf(address(0)), 20);
    }
}
