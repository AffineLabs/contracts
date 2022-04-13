import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "./.env") });

import { HardhatUserConfig } from "hardhat/types";
import { NetworkUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";

import "@nomiclabs/hardhat-etherscan";
import "hardhat-change-network";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "@primitivefi/hardhat-dodoc";
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

type ethNetwork = keyof typeof ethChainIds;
export const polygonChainIds = {
  mainnet: 137,
  mumbai: 80001,
};
type polygonNetwork = keyof typeof polygonChainIds;

const MNEMONIC = process.env.MNEMONIC || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY || "";
const ALCHEMY_ETH_KEY = process.env.ALCHEMY_ETH_KEY || "";
const ALCHEMY_POLYGON_KEY = process.env.ALCHEMY_POLYGON_KEY || "";

interface ethNetworkConfig {
  [key: string]: NetworkUserConfig;
}
function createNetworkConfig(network: ethNetwork | polygonNetwork, type: "eth" | "polygon" = "eth"): ethNetworkConfig {
  const isEth = type === "eth";
  const url: string = isEth
    ? `https://eth-${network}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`
    : `https://polygon-${network}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

  const networkConfig: NetworkUserConfig = {
    accounts: {
      count: 14,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: isEth ? ethChainIds[network as ethNetwork] : polygonChainIds[network as polygonNetwork],
    url,
  };
  const forkPort = isEth ? 8545 : 8546;
  const forkConfig: NetworkUserConfig = {
    ...networkConfig,
    url: `http://localhost:${forkPort}`,
    chainId: ethChainIds.hardhat,
  };
  return { [`${type}-${network}`]: networkConfig, [`${type}-${network}-fork`]: forkConfig };
}

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
    ...createNetworkConfig("mainnet"),
    ...createNetworkConfig("goerli"),
    ...createNetworkConfig("kovan"),
    ...createNetworkConfig("rinkeby"),
    ...createNetworkConfig("ropsten"),
    // Polygon networks
    ...createNetworkConfig("mainnet", "polygon"),
    ...createNetworkConfig("mumbai", "polygon"),
  },
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY,
      goerli: ETHERSCAN_API_KEY,
      polygon: POLYGONSCAN_API_KEY,
      polygonMumbai: POLYGONSCAN_API_KEY,
    },
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
    // We use both Openzeppelin and solmate ERC20, so exporting abi will throw "duplicate output destination" error
    except: [":ERC20$"],
  },
  contractSizer: {
    only: ["Vault|Staging"],
  },
  dodoc: {
    include: ["src"],
    exclude: ["test"],
    runOnCompile: false,
  },
  defender: {
    apiKey: process.env.DEFENDER_API_KEY || "",
    apiSecret: process.env.DEFENDER_API_SECRET || "",
  },
};

export default config;
