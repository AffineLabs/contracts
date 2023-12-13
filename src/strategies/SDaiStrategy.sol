// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {AccessStrategy} from "src/strategies/AccessStrategy.sol";
import {SlippageUtils} from "src/libs/SlippageUtils.sol";

import {ICurvePoolV2} from "src/interfaces/curve/ICurvePool.sol";
import {ISavingsDai} from "src/interfaces/maker/ISavingsDai.sol";

contract SDaiStrategy is AccessStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    ICurvePoolV2 public constant CURVE = ICurvePoolV2(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    int128 public constant C_ASSET_IDX = 1; // USDC index
    int128 public constant C_DAI_IDX = 0; // DAI index

    ISavingsDai public constant SDAI = ISavingsDai(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    constructor(AffineVault _vault, address[] memory strategists) AccessStrategy(_vault, strategists) {
        // approve curve to use dai and asset
        asset.safeApprove(address(CURVE), type(uint256).max);
        DAI.safeApprove(address(CURVE), type(uint256).max);

        // approve SDAI to use dai
        DAI.safeApprove(address(SDAI), type(uint256).max);
    }
    /*//////////////////////////////////////////////////////////////
                              INVEST/DIVEST
    //////////////////////////////////////////////////////////////*/

    function getSwapAmount(int128 from, int128 to, uint256 fromAmount) internal view returns (uint256 toAmount) {
        toAmount = 0;
        if (fromAmount > 0) {
            toAmount = CURVE.get_dy({x: from, y: to, dx: fromAmount});
        }
    }

    function _swapDaiToAsset(uint256 daiAmount) internal {
        CURVE.exchange({
            x: C_DAI_IDX,
            y: C_ASSET_IDX,
            dx: daiAmount,
            min_dy: getSwapAmount(C_DAI_IDX, C_ASSET_IDX, daiAmount).slippageDown(slippageBps)
        });
    }

    function _swapAssetToDai(uint256 assets) internal {
        CURVE.exchange({
            x: C_ASSET_IDX,
            y: C_DAI_IDX,
            dx: assets,
            min_dy: getSwapAmount(C_ASSET_IDX, C_DAI_IDX, assets).slippageDown(slippageBps)
        });
    }

    function _afterInvest(uint256 amount) internal virtual override {
        _swapAssetToDai(amount);
        SDAI.deposit(DAI.balanceOf(address(this)), address(this));
    }

    function _divest(uint256 amount) internal virtual override returns (uint256) {
        // tvl
        uint256 tvl = _investedAssets();

        // ratio of sdai to withdraw
        uint256 sDaiToWithdraw =
            amount < tvl ? SDAI.balanceOf(address(this)).mulDivDown(amount, tvl) : SDAI.balanceOf(address(this));

        uint256 receivedDai = SDAI.redeem(sDaiToWithdraw, address(this), address(this));
        uint256 prevAssets = asset.balanceOf(address(this));
        _swapDaiToAsset(receivedDai);
        uint256 receivedAssets = asset.balanceOf(address(this)) - prevAssets;
        asset.safeTransfer(address(vault), receivedAssets);
        return receivedAssets;
    }

    /*//////////////////////////////////////////////////////////////
                              SWAP SLIPPAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public slippageBps = 10; // swap slippage bps

    function setSlippageBps(uint256 _slippageBps) external {
        require(_slippageBps <= 10_000, "SDS: Invalid Slippage Bps");
        slippageBps = _slippageBps;
    }

    /*//////////////////////////////////////////////////////////////
                              VALUATIONS
    //////////////////////////////////////////////////////////////*/
    function _investedAssets() internal view returns (uint256) {
        uint256 daiAmount = SDAI.convertToAssets(SDAI.balanceOf(address(this)));
        return getSwapAmount(C_DAI_IDX, C_ASSET_IDX, daiAmount);
    }

    function totalLockedValue() external virtual override returns (uint256) {
        return _investedAssets();
    }
}
