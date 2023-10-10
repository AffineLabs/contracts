// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {AffinePass} from "./AffinePass.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";

contract AffinePassBridge is CCIPReceiver, Ownable {
    AffinePass public immutable affinePass;
    mapping(uint64 => bool) public whitelistedDestinationChains;
    mapping(uint64 => bool) public whitelistedSourceChains;
    mapping(address => bool) public whitelistedSenders;
    mapping(uint64 => address) public chainReciever;
    bool public paused = true;

    /// @notice  Used when the destination chain has not been whitelisted by the contract owner.
    error DestinationChainNotWhitelisted(uint64 destinationChainSelector);

    /// @notice Used when the source chain has not been whitelisted by the contract owner.
    error SourceChainNotWhitelisted(uint64 sourceChainSelector);

    /// @notice Used when the sender has not been whitelisted by the contract owner.
    error SenderNotWhitelisted(address sender);

    /// @notice Used when the bridge is paused.
    error BridgePaused();

    /// @notice Used when a token is bridged by anyone other than the owner.
    error OnlyOwnerCanBridge();

    /// @notice Used when `msg.value` is not enough to cover the fee.
    error FeeUnpaid();

    /// @notice  Event emitted when a message is sent to another chain.
    event BridgeRequest(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address sender, uint256 id);

    /// @notice Event emitted when a message is received from another chain.
    event BridgeReciept(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address receiver, uint256 id);

    constructor(
        AffinePass _affinePass,
        address router,
        uint64[] memory destinationChainSelectors,
        uint64[] memory sourceChainSelectors
    ) CCIPReceiver(router) {
        affinePass = _affinePass;
        for (uint256 i = 0; i < destinationChainSelectors.length; i = uncheckedInc(i)) {
            whitelistedDestinationChains[destinationChainSelectors[i]] = true;
        }
        for (uint256 i = 0; i < sourceChainSelectors.length; i = uncheckedInc(i)) {
            whitelistedSourceChains[sourceChainSelectors[i]] = true;
        }
    }

    receive() external payable {}

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setChainReciever(uint64 _chainSelector, address _reciever) external onlyOwner {
        chainReciever[_chainSelector] = _reciever;
    }

    function ccipFee(uint64 destinationChainSelector) external view returns (uint256) {
        Client.EVM2AnyMessage memory message =
            _buildCCIPMessage(chainReciever[destinationChainSelector], address(0), 1, address(0));

        return IRouterClient(i_router).getFee(destinationChainSelector, message);
    }

    function bridgePass(uint64 destinationChainSelector, address receiver, uint256 id)
        external
        payable
        returns (bytes32 messageId)
    {
        if (paused) revert BridgePaused();

        if (!whitelistedDestinationChains[destinationChainSelector]) {
            revert DestinationChainNotWhitelisted(destinationChainSelector);
        }

        if (affinePass.ownerOf(id) != msg.sender) revert OnlyOwnerCanBridge();

        Client.EVM2AnyMessage memory message =
            _buildCCIPMessage(chainReciever[destinationChainSelector], receiver, id, address(0));

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);
        if (msg.value < fee) revert FeeUnpaid();

        messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);

        emit BridgeRequest(messageId, destinationChainSelector, receiver, id);

        affinePass.bridgeBurn(id);

        return messageId;
    }

    function withdraw(uint256 amount) public onlyOwner {
        payable(owner()).transfer(amount);
    }

    function whitelistDestinationChain(uint64 _destinationChainSelector, bool _whitelist) external onlyOwner {
        whitelistedDestinationChains[_destinationChainSelector] = _whitelist;
    }

    function whitelistSourceChain(uint64 _sourceChainSelector, bool _whitelist) external onlyOwner {
        whitelistedSourceChains[_sourceChainSelector] = _whitelist;
    }

    function whitelistSender(address _sender, bool _whitelist) external onlyOwner {
        whitelistedSenders[_sender] = _whitelist;
    }

    function _buildCCIPMessage(address _receiver, address _address, uint256 _id, address _feeTokenAddress)
        internal
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(_address, _id), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array as no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
                ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
        return evm2AnyMessage;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Only whitwlisted source chains can send messages to this contract
        uint64 sourceChainSelector = message.sourceChainSelector;
        if (!whitelistedSourceChains[sourceChainSelector]) revert SourceChainNotWhitelisted(sourceChainSelector);

        // Only whitelisted senders can send messages to this contract
        address sender = abi.decode(message.sender, (address));
        if (!whitelistedSenders[sender]) revert SenderNotWhitelisted(sender);

        (address _address, uint256 _id) = abi.decode(message.data, (address, uint256));
        emit BridgeReciept(message.messageId, message.sourceChainSelector, _address, _id);

        affinePass.bridgeMint(_address, _id);
    }
}
