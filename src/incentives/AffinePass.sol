// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";



contract AffinePass is ERC721, ERC721Burnable, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    
    uint256 public constant MAX_SUPPLY = 3000;
    uint256 public constant MAX_SUPPLY_ACCOLADES = 270;
    uint256 public constant MAX_RESERVE_TOKENS = 988;
    uint256 public reserveTokens = 0;
    uint256 public constant MAX_WHITELIST_MINT = 1; // Maximum number of NFTs that can be minted by a whitelisted wallet
    uint256 public constant MAX_PUBLIC_MINT = 1; // Maximum number of NFTs that can be minted by a wallet
    bool public saleIsActive = false;
    bool public whitelistSaleIsActive = false;
    string public baseURI;
    bytes32 public merkleRoot;
    mapping(address => bool) public whitelistedBridge;
    mapping(address => bool) private _hasMintedGuaranteed;
    mapping(address => uint256) private _minted; // Total number of NFTs minted by each address
    mapping(address => uint256) private _whitelistMinted; // Number of NFTs minted by a whitelisted wallet
    IERC1155 public accolades;

    Counters.Counter private _tokenIdCounter;
    
    event WhitelistMerkleRootUpdated(bytes32 indexed merkleRoot);

    modifier onlyBridge() {
        require(whitelistedBridge[msg.sender], "Only bridge can call");
        _;
    }

    constructor( bytes32 _merkleRoot, address _accolades) 
        ERC721("Affine Pass", "APASS")          
    {
        merkleRoot = _merkleRoot;
        _tokenIdCounter.increment();
        whitelistedBridge[msg.sender] = true;

        // Initialize the ERC-1155 contract
        accolades = IERC1155(_accolades);
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
        emit WhitelistMerkleRootUpdated(merkleRoot);
    }

    function stopMint() public onlyOwner {
        saleIsActive = false;
        whitelistSaleIsActive = false;
    }

    function hasMintedWhitelist(address _address) public view returns (bool) {
        return _whitelistMinted[_address] > 0;
    }

    function hasMinted(address _address) public view returns (bool) {
        return _minted[_address] > 0;
    }

    function isWhitelisted(
        address user,
        bytes32[] memory proof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(proof, merkleRoot, node);
    }

    function isAccolade(address account) public view returns (bool) {
        return (
            accolades.balanceOf(account, 1) > 0 ||
            accolades.balanceOf(account, 2) > 0 ||
            accolades.balanceOf(account, 3) > 0
        );
    }

    function toggleWhitelistSale() public onlyOwner {
        whitelistSaleIsActive = !whitelistSaleIsActive;
    }

    function togglePublicSale() public onlyOwner {
        saleIsActive = !saleIsActive;
        whitelistSaleIsActive = false;
    }

    function mintReserve(uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        require(reserveTokens + amount <= MAX_RESERVE_TOKENS, "Exceeds max reserve supply");
        reserveTokens += amount;
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(owner(), tokenId);
        }
    }

    // Add a function to change the ERC-1155 contract address
    function setAccolades(address _accolades) public onlyOwner {
        accolades = IERC1155(_accolades);
    }

    function accoladeAllocation(address _address) public view returns (uint256 allocation){
        if(_hasMintedGuaranteed[_address]){
            return 0;
        } else if (accolades.balanceOf(_address, 1) > 0) {
            return 2;
        } else if (accolades.balanceOf(_address, 2) > 0) {
            return 3;
        } else if (accolades.balanceOf(_address, 3) > 0) {
            return 4;
        } else {
            return 0;
        }
    }

    // Modify the mintGuaranteed function
    function mintGuaranteed() public {
        require(!_hasMintedGuaranteed[_msgSender()], "Already minted");
        _hasMintedGuaranteed[_msgSender()] = true;

        uint256 quantity;
        if (accolades.balanceOf(_msgSender(), 1) > 0) {
            quantity = 2;
        } else if (accolades.balanceOf(_msgSender(), 2) > 0) {
            quantity = 3;
        } else if (accolades.balanceOf(_msgSender(), 3) > 0) {
            quantity = 4;
        } else {
            revert("No Affine Accolade");
        }

        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_msgSender(), tokenId);
        }
    }

    function hasRemainingSupply() public view returns (bool) {
        uint256 currentSupply = totalSupply();
        uint256 maxMintableSupply = MAX_SUPPLY - MAX_RESERVE_TOKENS - MAX_SUPPLY_ACCOLADES;
        return currentSupply < maxMintableSupply;
    }
    
    function mintWhitelist(bytes32[] memory proof) public payable {
        require(
            _msgSender() == owner() ||
                (whitelistSaleIsActive && isWhitelisted(_msgSender(), proof)),
            "Sale paused or not whitelisted"
        );
        require(hasRemainingSupply(), "Exceeds max supply");
        require(
            _whitelistMinted[_msgSender()] + 1 <= MAX_WHITELIST_MINT,
            "Exceeds max WL mint"
        );

        _whitelistMinted[_msgSender()] += 1;
        for (uint256 i = 0; i < 1; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_msgSender(), tokenId);
        }
    }

    function mint() public payable {
        require(_msgSender() == owner() || saleIsActive, "Sale is not active");
        require(hasRemainingSupply(), "Exceeds max supply");
        require(
            _minted[_msgSender()] + 1 <= MAX_PUBLIC_MINT,
            "Exceeds max public mint"
        );

        _minted[_msgSender()] += 1;
        for (uint256 i = 0; i < 1; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_msgSender(), tokenId);
        }
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

    // Overrides and Bridge

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function setIsWhitelistedBridge(address _bridge, bool _isWhitelisted) public onlyOwner {
        require(whitelistedBridge[_bridge] != _isWhitelisted, "Already set");
        whitelistedBridge[_bridge] = _isWhitelisted;
    }

    function bridgeMint(address to, uint256 tokenId) external onlyBridge {
        _safeMint(to, tokenId);
    }

    function bridgeBurn(uint256 tokenId) external onlyBridge {
        _burn(tokenId);
    }

}
