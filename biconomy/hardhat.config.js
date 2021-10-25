require("@nomiclabs/hardhat-ethers");
require("dotenv").config();

const MNEMONIC = process.env.DEPLOYER_SEED || "";
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.9",
  networks: {
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      accounts: {
        count: 10,
        initialIndex: 0,
        mnemonic: MNEMONIC,
        path: "m/44'/60'/0'/0",
      },
      chainId: 42,
    },
  },
};
