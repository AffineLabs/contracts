// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {Constants} from "src/libs/audited/Constants.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";
import {L2Vault} from "src/vaults/cross-chain-vault/audited/L2Vault.sol";
import {L1Vault} from "src/vaults/cross-chain-vault/audited/L1Vault.sol";
import {L1WormholeRouter} from "src/vaults/cross-chain-vault/wormhole/audited/L1WormholeRouter.sol";
import {BaseStrategy} from "src/strategies/audited/BaseStrategy.sol";
import {EmergencyWithdrawalQueue} from "src/vaults/cross-chain-vault/audited/EmergencyWithdrawalQueue.sol";
import {TestStrategy} from "./BaseVault.t.sol";
import {IRootChainManager} from "src/interfaces/IRootChainManager.sol";

/// @notice Test L1 vault specific functionalities.
contract L1VaultTest is TestPlus {
    using stdStorage for StdStorage;

    L1Vault vault;
    MockERC20 asset;
    IWormhole wormhole = IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);

    function setUp() public {
        forkEth();
        vault = Deploy.deployL1Vault();

        // depositFor will fail unless mapToken has been called. Let's use real ETH USDC addr (it is mapped)
        // solhint-disable-next-line max-line-length
        // https://github.com/maticnetwork/pos-portal/blob/88dbf0a88fd68fa11f7a3b9d36629930f6b93a05/contracts/root/RootChainManager/RootChainManager.sol#L169
        uint256 slot = stdstore.target(address(vault)).sig("asset()").find();
        bytes32 assetAddr = bytes32(uint256(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)));
        vm.store(address(vault), bytes32(slot), assetAddr);
        asset = MockERC20(vault.asset());
    }

    /// @notice Test sending TVL to L2 works.
    function testSendTVL() public {
        // user can call sendTVL
        vm.startPrank(alice);
        vault.sendTVL();
        assertTrue(vault.received() == false);
    }

    /// @notice Test processing fund request from L2 works.
    function testprocessFundRequest() public {
        // We need to either map the root token to the child token or
        // we need to use the correct already mapped addresses
        deal(address(asset), address(vault), 2e6, true);
        uint256 oldMsgCount = wormhole.nextSequence(address(vault.wormholeRouter()));
        uint256 amount = 1e6;

        vm.prank(address(vault));
        asset.approve(vault.predicate(), amount);

        vm.prank(address(vault.wormholeRouter()));
        vault.processFundRequest(1e6);
        assertTrue(wormhole.nextSequence(address(vault.wormholeRouter())) == oldMsgCount + 1);
    }

    /// @notice Test callback after receiving funds in bridge escrow works.
    function testafterReceive() public {
        BaseStrategy newStrategy1 = new TestStrategy(AffineVault(address(vault)));

        vm.startPrank(governance);
        vault.addStrategy(newStrategy1, 1);

        deal(address(asset), address(vault), 10_000, true);

        vm.startPrank(address(vault.bridgeEscrow()));
        vault.afterReceive();

        assertTrue(vault.received() == true);
        assertTrue(newStrategy1.balanceOfAsset() == 1);
    }

    /// @notice Test that profit is locked over a `LOCK_INTERVAL`.
    function testLockedProfit() public {
        vm.startPrank(governance);

        BaseStrategy newStrategy1 = new TestStrategy(AffineVault(address(vault)));
        vault.addStrategy(newStrategy1, 1000);

        deal(address(asset), address(newStrategy1), 1000, true);

        BaseStrategy[] memory strategies = new BaseStrategy[](1);
        strategies[0] = newStrategy1;
        vm.warp(vault.lastHarvest() + vault.LOCK_INTERVAL() + 1);

        vault.harvest(strategies);
        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.maxLockedProfit(), 1000);
        assertEq(vault.vaultTVL(), 1000);
    }
}
