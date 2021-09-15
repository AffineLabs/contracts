import { task } from "hardhat/config";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "./.env") });

import { HardhatUserConfig } from "hardhat/types";
import { NetworkUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";

import "hardhat-change-network";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-etherscan";

const ethChainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

const polygonChainIds = {
  mainnet: 137,
  mumbai: 80001,
};

const MNEMONIC = process.env.MNEMONIC || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const INFURA_API_KEY = process.env.INFURA_API_KEY || "";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});

function createETHNetworkConfig(network: keyof typeof ethChainIds): NetworkUserConfig {
  const url: string = "https://" + network + ".infura.io/v3/" + INFURA_API_KEY;
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: ethChainIds[network],
    url,
  };
}

function createPolygonNetworkConfig(network: keyof typeof polygonChainIds): NetworkUserConfig {
  const url: string = "https://rpc-" + network + ".maticvigil.com"
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: polygonChainIds[network],
    url,
  };
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: MNEMONIC,
      },
      chainId: ethChainIds.hardhat,
    },
    // Eth networks
    ethMainnet: createETHNetworkConfig("mainnet"),
    ethGoerli: createETHNetworkConfig("goerli"),
    ethKovan: createETHNetworkConfig("kovan"),
    ethRinkeby: createETHNetworkConfig("rinkeby"),
    ethRopsten: createETHNetworkConfig("ropsten"),
    // Polygon networks
    polygonMainnet:  createPolygonNetworkConfig("mainnet"),
    polygonMumbai: createPolygonNetworkConfig("mumbai")
  },
  solidity: {
    compilers: [
      {
        version: "0.7.3",
      },
    ],
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    enabled: process.env.REPORT_GAS ? true : false,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  mocha: {
    timeout: 900000,
  }
};

export default config;
