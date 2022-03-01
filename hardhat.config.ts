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
import "hardhat-abi-exporter";
import "@openzeppelin/hardhat-upgrades";
import "@openzeppelin/hardhat-defender";

import "./tasks/accounts";

export const ethChainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

export const polygonChainIds = {
  mainnet: 137,
  mumbai: 80001,
};

const MNEMONIC = process.env.MNEMONIC || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const ALCHEMY_ETH_KEY = process.env.ALCHEMY_ETH_KEY || "";
const ALCHEMY_POLYGON_KEY = process.env.ALCHEMY_POLYGON_KEY || "";

function createETHNetworkConfig(network: keyof typeof ethChainIds): NetworkUserConfig {
  const url: string = `https://eth-${network}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`;
  return {
    accounts: {
      count: 14,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: ethChainIds[network],
    url,
  };
}

function createPolygonNetworkConfig(network: keyof typeof polygonChainIds): NetworkUserConfig {
  const url: string = `https://polygon-${network}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;
  return {
    accounts: {
      count: 14,
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
  paths: { sources: "./src", cache: "./hh-cache" },
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
    polygonMainnet: createPolygonNetworkConfig("mainnet"),
    polygonMumbai: createPolygonNetworkConfig("mumbai"),

    mumbaiFork: {
      ...createPolygonNetworkConfig("mumbai"),
      url: "http://localhost:8545",
      chainId: ethChainIds.hardhat,
    },
    goerliFork: {
      ...createETHNetworkConfig("goerli"),
      url: "http://localhost:8546",
      chainId: ethChainIds.hardhat,
    },
  },
  solidity: {
    version: "0.8.10",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
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
    timeout: 3600000,
  },
  abiExporter: {
    runOnCompile: true,
    path: "./abi",
    clear: true,
    flat: true,
    spacing: 2,
  },
  defender: {
    apiKey: process.env.DEFENDER_API_KEY || "",
    apiSecret: process.env.DEFENDER_API_SECRET || "",
  },
};

export default config;
