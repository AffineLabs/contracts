// SPDX-License-Identifier:MIT
pragma solidity ^0.6.2;
// import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "https://github.com/opengsn/forwarder/blob/master/contracts/BaseRelayRecipient.sol";

contract AlpRelayRecipient is BaseRelayRecipient {
    uint256 public num;

    mapping(address => uint256) public balancesUsdc;
    mapping(address => uint256) public balancesAlpUsdc;

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

    function balanceOf(address user)
        public
        view
        returns (uint256 usdc, uint256 alpine)
    {
        return (balancesUsdc[user], balancesAlpUsdc[user]);
    }

    function getUsdc(uint256 amount) public {
        balancesUsdc[_msgSender()] += amount;
    }

    function mint(uint256 amountUsdc) public {
        require(balancesUsdc[_msgSender()] >= amountUsdc, "Not enough USDC");
        balancesUsdc[_msgSender()] -= amountUsdc;
        balancesAlpUsdc[_msgSender()] += amountUsdc;
    }

    function burn(uint256 amountAlpUsdc) public {
        require(
            balancesAlpUsdc[_msgSender()] >= amountAlpUsdc,
            "Not enough alpusdc"
        );
        balancesAlpUsdc[_msgSender()] -= amountAlpUsdc;
        balancesUsdc[_msgSender()] += amountAlpUsdc;
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
