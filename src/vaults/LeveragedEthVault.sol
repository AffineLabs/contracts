// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AffineBadges} from "src/nfts/AffineBadges.sol";
import {Vault} from "src/vaults/Vault.sol";

contract LeveragedEthVault is Vault {
    address public nftContractAddress;
    bool public nftMintingEnabled = false;

    function setNFTContractAddress(address _nftContractAddress) external onlyRole(GUARDIAN_ROLE) {
        require(nftContractAddress != _nftContractAddress, "Vault: Already at desired state.");
        nftContractAddress = _nftContractAddress;
    }

    function enableNFTMinting(bool _enabled) external onlyRole(GUARDIAN_ROLE) {
        require(nftMintingEnabled != _enabled, "Vault: Already at desired state.");
        nftMintingEnabled = true;
    }

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        if (nftMintingEnabled) {
            AffineBadges nftContract = AffineBadges(nftContractAddress);
            uint256 maxSupply = nftContract.maxSupply(1);
            uint256 userMinted = nftContract.mintCount(receiver, 1);
            uint256 currentSupply = nftContract.currentSupply(1);
            uint256 maxMint = nftContract.maxMint(1);
            if (userMinted < maxMint && currentSupply < maxSupply) {
                nftContract.mint(receiver, 1, 1, "");
            }
        }
        return shares;
    }
}
