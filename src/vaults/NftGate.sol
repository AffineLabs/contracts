// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC721} from "solmate/src/tokens/ERC721.sol";
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

abstract contract NftGate is AffineGovernable {
    ERC721 public accessNft;
    uint16 public withdrawalFeeWithNft;
    bool needNftToDeposit;
    bool nftDiscountActive;

    function setAccessNft(ERC721 _accessNft) external onlyGovernance {
        accessNft = _accessNft;
    }

    function setWithdrawalFeeWithNft(uint16 _newFee) external onlyGovernance {
        withdrawalFeeWithNft = _newFee;
    }

    function setNftProperties(bool _needNftToDeposit, bool _nftDiscountActive) external onlyGovernance {
        needNftToDeposit = _needNftToDeposit;
        nftDiscountActive = _nftDiscountActive;
    }

    function _checkNft(address owner) internal view {
        if (needNftToDeposit) require(accessNft.balanceOf(owner) > 0, "Caller has no access NFT");
    }
}
