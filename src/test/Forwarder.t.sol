// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TestPlus} from "./TestPlus.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Deploy} from "./Deploy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {L2Vault} from "src/vaults/cross-chain-vault/L2Vault.sol";
import {TwoAssetBasket} from "src/vaults/TwoAssetBasket.sol";
import {Forwarder} from "src/vaults/cross-chain-vault/Forwarder.sol";
import {MinimalForwarder} from "@openzeppelin/contracts/metatx/MinimalForwarder.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {Deploy} from "./Deploy.sol";

// Because of https://github.com/ethereum/solidity/issues/3556
abstract contract MockBasket {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {}
}

/// @notice Test the forwarder contract
contract ForwardTest is TestPlus {
    using stdStorage for StdStorage;

    L2Vault vault;
    TwoAssetBasket basket;
    ERC20 token = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    Forwarder forwarder;

    function setUp() public {
        forkPolygon();
        vault = Deploy.deployL2Vault();
        basket = Deploy.deployTwoAssetBasket(token);

        bytes32 tokenAddr = bytes32(uint256(uint160(address(token))));
        vm.store(address(vault), bytes32(stdstore.target(address(vault)).sig("asset()").find()), tokenAddr);

        token = MockERC20(address(vault.asset()));
        forwarder = new Forwarder();

        // // Update trusted forwarder in vault
        // uint256 slot = stdstore.target(address(vault)).sig("trustedForwarder()").find();
        // bytes32 forwarderAddr = bytes32(uint256(uint160(address(forwarder))));
        // vm.store(address(vault), bytes32(slot), forwarderAddr);

        // // Update trusted forwarder in basket
        // slot = stdstore.target(address(basket)).sig("trustedForwarder()").find();
        // vm.store(address(basket), bytes32(slot), forwarderAddr);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function getDomainSeparator(address forwarderAddr) public view returns (bytes32) {
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256("MinimalForwarder");
        bytes32 versionHash = keccak256("0.0.1");
        bytes32 domainSeparator = keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, forwarderAddr));
        return domainSeparator;
    }

    function getHashedReq(MinimalForwarder.ForwardRequest memory req) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"),
                req.from,
                req.to,
                req.value,
                req.gas,
                req.nonce,
                keccak256(req.data)
            )
        );
    }

    // /// @notice Test forwarding transactions in batch works.
    // function testDoubleDeposit() public {
    //     // send two deposits of 1 usdc to the l2vault
    //     address user = vm.addr(1);
    //     deal(address(token), user, 2e6);
    //     vm.startPrank(user);
    //     token.approve(address(vault), type(uint256).max);

    //     // get transaction data for a deposit of 1 usdc to L2Vault
    //     MinimalForwarder.ForwardRequest memory req1 = MinimalForwarder.ForwardRequest(
    //         user, address(vault), 0, 15e6, 0, abi.encodeCall(vault.deposit, (1e6, user))
    //     );
    //     bytes32 reqStructHash1 = getHashedReq(req1);

    //     // get transaction data for another deposit (this one has a nonce of 1)
    //     MinimalForwarder.ForwardRequest memory req2 = MinimalForwarder.ForwardRequest(
    //         user, address(vault), 0, 15e6, 1, abi.encodeCall(vault.deposit, (1e6, user))
    //     );
    //     bytes32 reqStructHash2 = getHashedReq(req2);

    //     bytes32 domainSeparator = getDomainSeparator(address(forwarder));
    //     // sign data
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, toTypedDataHash(domainSeparator, reqStructHash1));
    //     (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, toTypedDataHash(domainSeparator, reqStructHash2));

    //     MinimalForwarder.ForwardRequest[] memory requests = new MinimalForwarder.ForwardRequest[](2);
    //     requests[0] = req1;
    //     requests[1] = req2;
    //     forwarder.executeBatch(requests, abi.encodePacked(r, s, v, r2, s2, v2));
    // }

    // /// @notice Test forwarding works for both vaults and baskets.
    // function testTransactVaultAndBasket() public {
    //     // send one deposits of 1 usdc to L2Vault
    //     // try to start a rebalance in TwoAssetBasket
    //     address user = vm.addr(1);
    //     deal(address(token), user, 2e6);
    //     vm.startPrank(user);
    //     token.approve(address(vault), type(uint256).max);
    //     token.approve(address(basket), type(uint256).max);

    //     // get transaction data for a deposit of 1 usdc to L2Vault
    //     MinimalForwarder.ForwardRequest memory req1 = MinimalForwarder.ForwardRequest(
    //         user, address(vault), 0, 15e6, 0, abi.encodeCall(vault.deposit, (1e6, user))
    //     );

    //     MinimalForwarder.ForwardRequest memory req2 = MinimalForwarder.ForwardRequest(
    //         user, address(basket), 0, 15e6, 1, abi.encodeCall(MockBasket.deposit, (1e6, user))
    //     );

    //     bytes32 domainSeparator = getDomainSeparator(address(forwarder));
    //     // sign data
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, toTypedDataHash(domainSeparator, getHashedReq(req1)));
    //     (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(1, toTypedDataHash(domainSeparator, getHashedReq(req2)));

    //     MinimalForwarder.ForwardRequest[] memory requests = new MinimalForwarder.ForwardRequest[](2);
    //     requests[0] = req1;
    //     requests[1] = req2;
    //     forwarder.executeBatch(requests, abi.encodePacked(r, s, v, r2, s2, v2));

    //     assertTrue(vault.balanceOf(user) > 0);
    //     assertTrue(basket.balanceOf(user) > 0);
    // }
}
