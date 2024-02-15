// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {BaseStrategy as Strategy} from "src/strategies/BaseStrategy.sol";
import {AffineGovernable} from "src/utils/AffineGovernable.sol";
import {BridgeEscrow} from "./escrow/BridgeEscrow.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";
import {VaultErrors} from "src/libs/VaultErrors.sol";

/**
 * @notice A core contract to be inherited by the L1 and L2 vault contracts. This contract handles adding
 * and removing strategies, investing in (and divesting from) strategies, harvesting gains/losses, and
 * strategy liquidation.
 */

abstract contract BaseVaultV2 is AccessControlUpgradeable, AffineGovernable {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    ERC20 _asset;

    /// @notice The token that the vault takes in and tries to get more of, e.g. USDC
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /**
     * @dev Initialize the vault.
     * @param _governance The governance address.
     * @param vaultAsset The vault's input asset.
     * @param _wormholeRouter The wormhole router.
     * @param _bridgeEscrow Bridge escrow for receiving cross-chain transfers.
     */
    function baseInitialize(address _governance, ERC20 vaultAsset, address _wormholeRouter, BridgeEscrow _bridgeEscrow)
        internal
        virtual
    {
        governance = _governance;
        _asset = vaultAsset;
        wormholeRouter = _wormholeRouter;
        bridgeEscrow = _bridgeEscrow;

        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(HARVESTER, governance);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN REBALANCING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A contract used for sending and receiving messages via wormhole.
     * @dev We use an address since we need to cast this to the L1 and L2 router types.
     */
    address public wormholeRouter;
    /// @notice A "BridgeEscrow" contract for sending and receiving `token` across a bridge.
    BridgeEscrow public bridgeEscrow;

    uint256 constant MAX_BPS = 10_000;
    uint256 public constant LOCK_INTERVAL = 24 hours;

    /**
     * @notice Update the address of the wormhole router.
     * @param _router The new router.
     */
    function setWormholeRouter(address _router) external onlyGovernance {
        emit WormholeRouterSet({oldRouter: wormholeRouter, newRouter: _router});
        wormholeRouter = _router;
    }
    
    /**
     * @notice Update the address of the bridge escrow.
     * @param _escrow The new escrow.
     */

    function setBridgeEscrow(BridgeEscrow _escrow) external onlyGovernance {
        emit BridgeEscrowSet({oldEscrow: address(bridgeEscrow), newEscrow: address(_escrow)});
        bridgeEscrow = _escrow;
    }

    /**
     * @notice Emitted when the wormhole router is updated.
     * @param oldRouter The old router.
     * @param newRouter The new router.
     */
    event WormholeRouterSet(address indexed oldRouter, address indexed newRouter);
    /**
     * @notice Emitted when the escorw is updated.
     * @param oldEscrow The old router.
     * @param newEscrow The new router.
     */
    event BridgeEscrowSet(address indexed oldEscrow, address indexed newEscrow);

    /*//////////////////////////////////////////////////////////////
                             AUTHENTICATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Role with authority to call "harvest", i.e. update this vault's tvl
    bytes32 public constant HARVESTER = keccak256("HARVESTER");



    /*//////////////////////////////////////////////////////////////
                               STRATEGIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The total amount of underlying assets held in strategies at the time of the last harvest.
    uint256 public totalStrategyHoldings;

    /// @notice The total amount of the underlying asset the vault has.
    function vaultTVL() public view returns (uint256) {
        return _asset.balanceOf(address(this)) + totalStrategyHoldings;
    }

    /**
     * @notice Assess fees.
     * @dev This is called during harvest() to assess management fees.
     */
    function _assessFees() internal virtual {}
}
