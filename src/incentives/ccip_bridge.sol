// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

interface IAffinePass {
    function bridgeMint(address to, uint256 tokenId) external;
    function bridgeBurn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}


contract AffineBridge is CCIPReceiver, Ownable {
    IAffinePass public affinePass;
    mapping(uint64 => bool) public whitelistedDestinationChains;
    mapping(uint64 => bool) public whitelistedSourceChains;
    mapping(address => bool) public whitelistedSenders;
    mapping(uint64 => address) public chainReciever;
    bool public paused = true;

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error DestinationChainNotWhitelisted(uint64 destinationChainSelector); // Used when the destination chain has not been whitelisted by the contract owner.
    error SourceChainNotWhitelisted(uint64 sourceChainSelector); // Used when the source chain has not been whitelisted by the contract owner.
    error SenderNotWhitelisted(address sender); // Used when the sender has not been whitelisted by the contract owner.

    // Event emitted when a message is sent to another chain.
    event BridgeRequest(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address sender,
        uint256 id 
    );

    // Event emitted when a message is received from another chain.
    event BridgeReciept(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address receiver,
        uint256 id
    );

    modifier onlyWhitelistedDestinationChain(uint64 _destinationChainSelector) {
        if (!whitelistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotWhitelisted(_destinationChainSelector);
        _;
    }

    modifier onlyWhitelistedSourceChain(uint64 _sourceChainSelector) {
        if (!whitelistedSourceChains[_sourceChainSelector])
            revert SourceChainNotWhitelisted(_sourceChainSelector);
        _;
    }

    modifier onlyWhitelistedSenders(address _sender) {
        if (!whitelistedSenders[_sender]) revert SenderNotWhitelisted(_sender);
        _;
    }

    modifier canBridge() {
        require(!paused, "Bridging is paused");
        _;
    }

    constructor(address router) CCIPReceiver(router) {
        // Polygon
        whitelistedDestinationChains[4051577828743386545] = true;
        whitelistedSourceChains[4051577828743386545] = true;

        // ETH
        whitelistedDestinationChains[5009297550715157269] = true;
        whitelistedSourceChains[5009297550715157269] = true;
    }

    fallback() external payable { }
    receive() external payable { }

    function setAffinePassAddress(address _affinePass) external onlyOwner {
        affinePass = IAffinePass(_affinePass);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setChainReciever(uint64 _chainId, address _router) external onlyOwner {
        chainReciever[_chainId] = _router;
    }

    function bridgePass(
        uint64 destinationChainSelector,
        address receiver,
        uint256 id
    ) external onlyWhitelistedDestinationChain(destinationChainSelector) canBridge returns (bytes32 messageId) {
        require(affinePass.ownerOf(id) == msg.sender, "Not owner of token");

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(
            chainReciever[destinationChainSelector],
            receiver,
            id,
            address(0)
        );

        uint256 fee = IRouterClient(i_router).getFee(
            destinationChainSelector,
            message
        );

        if (fee > address(this).balance)
            revert NotEnoughBalance(address(this).balance, fee);

        messageId = IRouterClient(i_router).ccipSend{value: fee}(
            destinationChainSelector,
            message
        );

        emit BridgeRequest(messageId, destinationChainSelector, receiver, id);

        affinePass.bridgeBurn(id);

        return messageId;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function whitelistDestinationChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedDestinationChains[_destinationChainSelector] = true;
    }

    function denylistDestinationChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedDestinationChains[_destinationChainSelector] = false;
    }

    function whitelistSourceChain(
        uint64 _sourceChainSelector
    ) external onlyOwner {
        whitelistedSourceChains[_sourceChainSelector] = true;
    }

    function denylistSourceChain(
        uint64 _sourceChainSelector
    ) external onlyOwner {
        whitelistedSourceChains[_sourceChainSelector] = false;
    }
    
    function whitelistSender(address _sender) external onlyOwner {
        whitelistedSenders[_sender] = true;
    }

    function denySender(address _sender) external onlyOwner {
        whitelistedSenders[_sender] = false;
    }

    function _buildCCIPMessage(
        address _receiver,
        address _address,
        uint256 _id,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(_address, _id), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array aas no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
        return evm2AnyMessage;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override onlyWhitelistedSourceChain(message.sourceChainSelector) onlyWhitelistedSenders(abi.decode(message.sender, (address))){
        (address _address, uint256 _id) = abi.decode(message.data, (address, uint256));
        emit BridgeReciept(message.messageId, message.sourceChainSelector, _address, _id);
        affinePass.bridgeMint(_address, _id);
    }

}
