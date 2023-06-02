// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AffineBadges} from "src/nfts/AffineBadges.sol";
import {Vault} from "src/vaults/Vault.sol";

contract MyVault is Vault {
    address public nftContractAddress;

    constructor(address _nftContractAddress) {
        nftContractAddress = _nftContractAddress;
    }

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        AffineBadges nftContract = AffineBadges(nftContractAddress);
        uint256 maxSupply = nftContract.maxSupply(1);
        uint256 userMinted = nftContract.mintCount(receiver, 1);
        uint256 currentSupply = nftContract.currentSupply(1);
        uint256 maxMint = nftContract.maxMint(1);
        if (userMinted < maxMint && currentSupply < maxSupply) {
            nftContract.mint(receiver, 1, 1, "");
        }
        return shares;
    }
}
