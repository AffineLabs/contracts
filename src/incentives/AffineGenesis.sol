// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "erc721a/contracts/ERC721A.sol";

contract AffineGenesis is ERC721A, Ownable {
    uint256 public constant MAX_SUPPLY = 5000;
    uint256 public constant MAX_DEV_TOKENS = 5;
    uint256 public devTokens;
    uint256 private _price = 0;
    uint256 public constant MAX_MINT_PER_TX = 5;
    uint256 public constant MAX_WHITELIST_MINT = 2;
    uint256 public constant MAX_PUBLIC_MINT = 5;
    bool public saleIsActive = false;
    bool public whitelistSaleIsActive = false;
    string public baseURI;
    bytes32 public merkleRoot;

    mapping(address => uint256) private _minted;
    mapping(address => uint256) private _whitelistMinted;
    mapping(address => uint256) private _mintedInTx;

    event WhitelistMerkleRootUpdated(bytes32 indexed merkleRoot);

    constructor(bytes32 _merkleRoot) ERC721A("Affine Genesis", "AG") {
        devTokens = 0;
        merkleRoot = _merkleRoot;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
        emit WhitelistMerkleRootUpdated(merkleRoot);
    }

    function isWhitelisted(address user, bytes32[] memory proof) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(proof, merkleRoot, node);
    }

    function setPrice(uint256 newPrice) public onlyOwner {
        _price = newPrice;
    }

    function getPrice() public view returns (uint256) {
        return _price;
    }

    function toggleWhitelistSale() public onlyOwner {
        whitelistSaleIsActive = !whitelistSaleIsActive;
    }

    function togglePublicSale() public onlyOwner {
        saleIsActive = !saleIsActive;
        whitelistSaleIsActive = false;
    }

    function mintDev(uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        require(devTokens + amount <= MAX_DEV_TOKENS, "Exceeds max dev supply");
        devTokens += amount;
        _mint(_msgSender(), amount);
    }

    function mintWhitelist(uint256 quantity, bytes32[] memory proof) public payable {
        require(
            _msgSender() == owner() || (whitelistSaleIsActive && isWhitelisted(_msgSender(), proof)),
            "Sale paused or not whitelisted"
        );
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        require(msg.value >= _price * quantity, "Insufficient payment");
        require(quantity <= MAX_MINT_PER_TX, "Exceeds max NFTs per transaction");
        require(_whitelistMinted[_msgSender()] + quantity <= MAX_WHITELIST_MINT, "Exceeds max WL mint");

        _whitelistMinted[_msgSender()] += quantity;
        _mint(_msgSender(), quantity);
    }

    function mint(uint256 quantity) public payable {
        require(_msgSender() == owner() || saleIsActive, "Sale is not active");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        require(msg.value >= _price * quantity, "Insufficient payment");
        require(quantity <= MAX_MINT_PER_TX, "Exceeds max NFTs per transaction");
        require(_minted[_msgSender()] + quantity <= MAX_PUBLIC_MINT, "Exceeds max public mint");

        _minted[_msgSender()] += quantity;
        _mint(_msgSender(), quantity);
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory URI) public onlyOwner {
        baseURI = URI;
    }
}
