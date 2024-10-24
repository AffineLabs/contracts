// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

interface ISymVaultFactory {
    struct InitParams {
        address collateral;
        address delegator;
        address slasher;
        address burner;
        uint48 epochDuration;
        bool depositWhitelist;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
    }

    function create(uint64 version, address owner_, bytes calldata data) external returns (address);
    function implementation(uint64) external view returns (address);
}
