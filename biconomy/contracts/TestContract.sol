// SPDX-License-Identifier:MIT
pragma solidity ^0.6.2;
// import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "https://github.com/opengsn/forwarder/blob/master/contracts/BaseRelayRecipient.sol";

contract MyContract is BaseRelayRecipient {
    uint256 public num;

    /**
     * Set the trustedForwarder address either in constructor or
     * in other init function in your contract
     */
    constructor(address _trustedForwarder) public {
        trustedForwarder = _trustedForwarder;
    }

    function increment() public {
        num += 1;
    }

    function decrement() public {
        num -= 1;
    }

    // TODO: make this onlyowner
    function setTrustedForwarder(address _trustedForwarder) public {
        trustedForwarder = _trustedForwarder;
    }

    /**
     * OPTIONAL
     * You should add one setTrustedForwarder(address _trustedForwarder)
     * method with onlyOwner modifier so you can change the trusted
     * forwarder address to switch to some other meta transaction protocol
     * if any better protocol comes tomorrow or current one is upgraded.
     */

    /**
     * Override this function.
     * This version is to keep track of BaseRelayRecipient you are using
     * in your contract.
     */
    function versionRecipient() external view override returns (string memory) {
        return "1";
    }
}
