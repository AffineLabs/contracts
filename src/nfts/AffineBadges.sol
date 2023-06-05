// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract AffineBadges is ERC1155, AccessControl, ERC1155Supply {
    mapping(uint256 => bool) public mintAllowed;
    mapping(uint256 => uint256) public maxSupply;
    mapping(uint256 => uint256) public maxMint;
    mapping(uint256 => uint256) public currentSupply;
    mapping(address => mapping(uint256 => uint256)) public mintCount;
    bool public mintActive;
    string public name = "Affine Badges";
    string public symbol = "ABADGE";

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    modifier mintable(uint256 id) {
        require(mintAllowed[id], "AffineBadges: Minting not allowed for given ID.");
        require(mintActive, "AffineBadges: Minting paused.");
        _;
    }

    constructor() ERC1155("") {
        // Dev: Initial setup for first token
        mintAllowed[1] = true;
        maxMint[1] = 1;
        maxSupply[1] = 225;
        _grantRole(OWNER_ROLE, _msgSender());
    }

    function setMaxMint(uint256 _maxMint, uint256 id) public onlyRole(OWNER_ROLE) {
        maxMint[id] = _maxMint;
    }

    function setURI(string memory newuri) public onlyRole(OWNER_ROLE) {
        _setURI(newuri);
    }

    function setMaxSupply(uint256 id, uint256 supply) public onlyRole(OWNER_ROLE) {
        maxSupply[id] = supply;
    }

    function setCanMint(address account) public onlyRole(OWNER_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    function setMintActive(bool _mintActive) public onlyRole(OWNER_ROLE) {
        require(_mintActive != mintActive, "AffineBadges: Desired state is already set.");
        mintActive = _mintActive;
    }

    function setMintAllowed(uint256 id, bool _mintAllowed) public onlyRole(OWNER_ROLE) {
        mintAllowed[id] = _mintAllowed;
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        mintable(id)
        onlyRole(MINTER_ROLE)
    {
        uint256 minted = mintCount[account][id];
        require(currentSupply[id] + amount <= maxSupply[id], "AffineBadges: Mint exceeds max supply.");
        require(minted + amount <= maxMint[id], "AffineBadges: Mint exceeds max per wallet.");
        mintCount[account][id] += amount;
        currentSupply[id] += amount;
        _mint(account, id, amount, data);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
