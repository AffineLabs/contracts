// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {Deploy} from "./Deploy.sol";

import {L2Vault} from "../polygon/L2Vault.sol";
import {L1Vault} from "../ethereum/L1Vault.sol";
import {IWormhole} from "../interfaces/IWormhole.sol";
import {L1WormholeRouter} from "../ethereum/L1WormholeRouter.sol";
import {L2WormholeRouter} from "../polygon/L2WormholeRouter.sol";
import {WormholeRouter} from "../WormholeRouter.sol";
import {Constants} from "../Constants.sol";

// This contract exists solely to test the internal view
contract MockRouter is L2WormholeRouter {
    function validateWormholeMessageEmitter(IWormhole.VM memory vm) public view {
        return _validateWormholeMessageEmitter(vm);
    }
}

contract L2WormholeRouterTest is TestPlus {
    using stdStorage for StdStorage;

    L2WormholeRouter router;
    L2Vault vault;
    address rebalancer = governance;

    function setUp() public {
        vm.createSelectFork("polygon", 31_824_532);
        vault = Deploy.deployL2Vault();
        router = L2WormholeRouter(vault.wormholeRouter());

        // See https://book.wormhole.com/reference/contracts.html for addresses
        router.initialize(IWormhole(0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7), vault, address(0), uint16(0));
    }

    function testReinitializeFails() public {
        address maliciousWormhole = makeAddr("maliciousWormhole");
        vm.expectRevert("Initializable: contract is already initialized");
        router.initialize(IWormhole(maliciousWormhole), vault, address(0), uint16(0));
    }

    function testWormholeConfigUpdates() public {
        // update wormhole address
        changePrank(governance);
        router.setWormhole(IWormhole(address(this)));
        assertEq(address(router.wormhole()), address(this));

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        router.setWormhole(IWormhole(address(0)));

        // update consistencyLevel
        changePrank(governance);
        router.setConsistencyLevel(100);
        assertEq(router.consistencyLevel(), 100);

        changePrank(alice);
        vm.expectRevert("Only Governance.");
        router.setConsistencyLevel(0);
    }

    function testTransferReport() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.reportTransferredFund(0);

        uint256 transferAmount = 100;
        bytes memory payload = abi.encode(Constants.L2_FUND_TRANSFER_REPORT, transferAmount);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.reportTransferredFund(transferAmount);
    }

    function testMessageValidation() public {
        MockRouter mockRouter = new MockRouter();
        uint16 emitter = uint16(1);
        address otherLayerRouter = makeAddr("otherLayerRouter");
        mockRouter.initialize(IWormhole(address(0)), vault, otherLayerRouter, emitter);

        IWormhole.VM memory vaa;
        vaa.emitterChainId = emitter;
        vaa.emitterAddress = bytes32(uint256(uint160(address(0))));
        vm.expectRevert("Wrong emitter address");
        mockRouter.validateWormholeMessageEmitter(vaa);

        IWormhole.VM memory vaa1;
        vaa1.emitterChainId = uint16(0);
        vaa1.emitterAddress = bytes32(uint256(uint160(otherLayerRouter)));
        emit log_named_bytes32("left padded addr: ", bytes32(uint256(uint160(otherLayerRouter))));
        vm.expectRevert("Wrong emitter chain");
        mockRouter.validateWormholeMessageEmitter(vaa1);

        // This will work
        IWormhole.VM memory goodVaa;
        goodVaa.emitterChainId = emitter;
        goodVaa.emitterAddress = bytes32(uint256(uint160(otherLayerRouter)));
        mockRouter.validateWormholeMessageEmitter(goodVaa);
    }

    function testRequestFunds() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.requestFunds(0);

        uint256 requestAmount = 100;
        bytes memory payload = abi.encode(Constants.L2_FUND_REQUEST, requestAmount);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.requestFunds(requestAmount);
    }

    function testReceiveFunds() public {
        uint256 l1TransferAmount = 500;

        // Mock call to wormhole.parseAndVerifyVM()
        IWormhole.VM memory vaa;
        vaa.nonce = 20;
        vaa.payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, l1TransferAmount);

        bool valid = true;
        string memory reason = "";

        bytes memory wormholeReturnData = abi.encode(vaa, valid, reason);

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VAA_FROM_L1_TRANSFER")),
            wormholeReturnData
        );

        // Make sure that bridgEscrow has funds to send to the vault
        deal(vault.asset(), address(vault.bridgeEscrow()), l1TransferAmount);

        // Make sure that l1TotalLockedValue is above amount being transferred to L2 (or else we get an underflow)
        vm.store(
            address(vault),
            bytes32(stdstore.target(address(vault)).sig("l1TotalLockedValue()").find()),
            bytes32(uint256(l1TransferAmount))
        );

        // You need the rebalancer role in the vault in order to call this function
        // Governance gets the rebalancer role
        vm.prank(governance);
        router.receiveFunds("VAA_FROM_L1_TRANSFER");

        // Nonce is updated
        assertEq(router.nextValidNonce(), vaa.nonce + 1);

        // Assert that funds get cleared
        assertEq(ERC20(vault.asset()).balanceOf(address(vault)), l1TransferAmount);
    }

    function testReceiveFundsInvariants() public {
        // You must have the rebalancer role to call receiveFunds
        vm.prank(alice);
        vm.expectRevert("Only Rebalancer");
        router.receiveFunds("VAA_FROM_L1_TRANSFER");

        // If wormhole says the vaa is bad, we revert
        // Mock call to wormhole.parseAndVerifyVM()
        IWormhole.VM memory vaa;
        bool valid = false;
        string memory reason = "Reason string from wormhole contract";

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VAA_FROM_L1_TRANSFER")),
            abi.encode(vaa, valid, reason)
        );

        vm.startPrank(rebalancer);
        vm.expectRevert(bytes(reason));
        router.receiveFunds("VAA_FROM_L1_TRANSFER");
        vm.clearMockedCalls();

        // If the nonce is old, we revert
        IWormhole.VM memory vaa2;
        vaa2.nonce = 10;

        // Make sure that l1TotalLockedValue is above amount being transferred to L2 (or else we get an underflow)
        vm.store(
            address(router),
            bytes32(stdstore.target(address(router)).sig("nextValidNonce()").find()),
            bytes32(uint256(11))
        );

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("VAA_FROM_L1_TRANSFER")),
            abi.encode(vaa2, true, "")
        );

        vm.expectRevert("Old transaction");
        router.receiveFunds("VAA_FROM_L1_TRANSFER");
    }

    function testReceiveTVL() public {
        // Mock call to wormhole.parseAndVerifyVM()
        uint256 tvl = 1000;
        bool received = true;

        IWormhole.VM memory vaa;
        vaa.payload = abi.encode(Constants.L1_TVL, tvl, received);

        vm.mockCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.parseAndVerifyVM, ("L1_TVL_VAA")),
            abi.encode(vaa, true, "")
        );

        vm.prank(rebalancer);
        vm.expectCall(address(vault), abi.encodeCall(vault.receiveTVL, (tvl, received)));
        router.receiveTVL("L1_TVL_VAA");

        assertEq(router.nextValidNonce(), 1);
    }

    function testReceiveTVLInvariants() public {
        // You must have the rebalancer role to call this receiveTVL
        vm.prank(alice);
        vm.expectRevert("Only Rebalancer");
        router.receiveFunds("foo");

        // The other invariants are the same as receiveFunds()
    }
}

contract L1WormholeRouterTest is TestPlus {
    using stdStorage for StdStorage;

    L1WormholeRouter router;
    L1Vault vault;
    address rebalancer = governance;

    function setUp() public {
        vm.createSelectFork("ethereum", 14_971_385);
        vault = Deploy.deployL1Vault();
        router = L1WormholeRouter(vault.wormholeRouter());

        // See https://book.wormhole.com/reference/contracts.html for addresses
        router.initialize(IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B), vault, address(0), uint16(0));
    }

    function testReinitializeFails() public {
        address maliciousWormhole = makeAddr("maliciousWormhole");
        vm.expectRevert("Initializable: contract is already initialized");
        router.initialize(IWormhole(maliciousWormhole), vault, address(0), uint16(0));
    }

    function testReportTVL() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.reportTVL(0, false);

        uint256 tvl = 50_000;
        bool received = true;
        bytes memory payload = abi.encode(Constants.L1_TVL, tvl, received);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.reportTVL(tvl, received);
    }

    function testReportTransferredFund() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only vault");
        router.reportTransferredFund(0);

        uint256 requestAmount = 100;
        bytes memory payload = abi.encode(Constants.L1_FUND_TRANSFER_REPORT, requestAmount);
        vm.expectCall(
            address(router.wormhole()),
            abi.encodeCall(IWormhole.publishMessage, (uint32(0), payload, router.consistencyLevel()))
        );

        vm.prank(address(vault));
        router.reportTransferredFund(requestAmount);
    }

    function testReceiveFunds() public {
        // Only invariant is that the vault is the only caller
        vm.prank(alice);
        vm.expectRevert("Only Rebalancer");
        router.receiveFunds("", "");

        uint256 l2TransferAmount = 500;

        // Mock call to wormhole.parseAndVerifyVM()
        IWormhole.VM memory vaa;
        vaa.nonce = 2;
        vaa.payload = abi.encode(Constants.L2_FUND_TRANSFER_REPORT, l2TransferAmount);

        bytes memory fakeVAA = bytes("VAA_FROM_L2_TRANSFER");
        vm.mockCall(
            address(router.wormhole()), abi.encodeCall(IWormhole.parseAndVerifyVM, (fakeVAA)), abi.encode(vaa, true, "")
        );

        // We use an empty exitProof since we are just going to mock the call to the bridgeEscrow
        bytes memory clearFundData = abi.encodeCall(vault.bridgeEscrow().l1ClearFund, (l2TransferAmount, ""));
        vm.mockCall(address(vault.bridgeEscrow()), clearFundData, "");
        vm.expectCall(address(vault.bridgeEscrow()), clearFundData);
        vm.prank(rebalancer);
        router.receiveFunds(fakeVAA, "");

        // Nonce is updated
        assertEq(router.nextValidNonce(), vaa.nonce + 1);
    }

    function testReceiveFundRequest() public {
        vm.prank(alice);
        vm.expectRevert("Only Rebalancer");
        router.receiveFundRequest("");

        // Mock call to wormhole.parseAndVerifyVM()
        uint256 requestAmount = 200;
        IWormhole.VM memory vaa;
        vaa.payload = abi.encode(Constants.L2_FUND_REQUEST, requestAmount);

        bytes memory fakeVAA = bytes("L2_FUND_REQ");
        vm.mockCall(
            address(router.wormhole()), abi.encodeCall(IWormhole.parseAndVerifyVM, (fakeVAA)), abi.encode(vaa, true, "")
        );

        // We call processFundRequest
        // We mock the call to the above function since we it is tested separately
        bytes memory processData = abi.encodeCall(vault.processFundRequest, (requestAmount));
        vm.mockCall(address(vault), processData, "");
        vm.expectCall(address(vault), processData);
        vm.prank(rebalancer);
        router.receiveFundRequest(fakeVAA);
    }
}
