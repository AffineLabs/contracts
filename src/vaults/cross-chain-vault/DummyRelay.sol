// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

/// @dev this is used in place of BaseRelayRecipient
/// @dev helps to keep the proxy storage layout unchanged
abstract contract DummyRelay {
    address private _trustedForwarder;

    function _setTrustedForwarder(address _forwarder) internal {
        _trustedForwarder = _forwarder;
    }

    function trustedForwarder() public view virtual returns (address) {
        return _trustedForwarder;
    }
}
