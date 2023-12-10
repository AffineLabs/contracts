// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {TwoAssetBasket} from "src/vaults/TwoAssetBasket.sol";
import {BaseStrategy} from "src/strategies/BaseStrategy.sol";
import {Deploy} from "./Deploy.sol";
import {ERC4626Router} from "src/vaults/cross-chain-vault/router/ERC4626Router.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {IWETH} from "src/interfaces/IWETH.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/L1Vault.sol";
import {Router} from "src/vaults/cross-chain-vault/router/Router.sol";

/// @notice Test functionalities of the router contract.
contract L2RouterTest is TestPlus {
    using stdStorage for StdStorage;

    ERC20 token = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    L2Vault vault;
    ERC4626Router router;
    TwoAssetBasket basket;

    function setUp() public {
        forkPolygon();
        vault = Deploy.deployL2Vault();
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(token))));
        vm.store(address(vault), bytes32(slot), tokenAddr);
        router = new ERC4626Router("");
        basket = Deploy.deployTwoAssetBasket(token);
    }

    /// @notice Test that the router contract can handle multiple deposits.
    function testMultipleDeposits() public {
        address user = alice;
        deal(address(token), user, 10e6);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(router.depositToVault.selector, IERC4626(address(basket)), user, 1e6, 0);
        data[1] = abi.encodeWithSelector(router.depositToVault.selector, IERC4626(address(vault)), user, 1e6, 0);
        vm.startPrank(user);
        token.approve(address(router), 2e6);
        router.approve(token, address(vault), 2e6);
        router.approve(token, address(basket), 2e6);
        router.multicall(data);
        assert(vault.balanceOf(user) > 0);
        assert(basket.balanceOf(user) > 0);
    }
}

/// @notice Test functionalities of the router contract.
contract L1RouterTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    Router router;
    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        forkEth();
        vault = Deploy.deployL2Vault();
        router = new Router("", weth);
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 tokenAddr = bytes32(uint256(uint160(address(weth))));
        vm.store(address(vault), bytes32(slot), tokenAddr);
    }

    function testDepositEth() public {
        vm.deal(alice, 1 ether);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(router.depositNative, ());
        data[1] = abi.encodeWithSelector(router.deposit.selector, IERC4626(address(vault)), alice, 1 ether, 0);

        vm.startPrank(alice);
        router.approve(ERC20(address(weth)), address(vault), 1 ether);
        router.multicall{value: 1 ether}(data);
        assert(vault.balanceOf(alice) > 0);
    }
}
