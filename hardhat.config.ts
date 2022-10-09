import { config as dotenvConfig } from "dotenv";
import { resolve, join, sep } from "path";
dotenvConfig({ path: resolve(__dirname, "./.env") });

import { HardhatUserConfig, NetworkUserConfig } from "hardhat/types";

import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";

import "@nomiclabs/hardhat-etherscan";
import "hardhat-change-network";
import "hardhat-abi-exporter";
import "@primitivefi/hardhat-dodoc";
import "@openzeppelin/hardhat-upgrades";
import "@openzeppelin/hardhat-defender";

import "./tasks/accounts";
import "./tasks/unblock";
import { ethChainIds, polygonChainIds, ethNetwork, polygonNetwork } from "./scripts/utils/constants/types";

import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";

// Ignore foundry test files during hardhat compilation.
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const paths = await runSuper();
  // Don't compile anything under src/test/
  return paths.filter((p: string) => !p.includes(join("src", "test") + sep));
});

const MNEMONIC = process.env.MNEMONIC || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY || "";
const ALCHEMY_ETH_GOERLI_KEY = process.env.ALCHEMY_ETH_GOERLI_KEY || "";
const ALCHEMY_POLYGON_MUMBAI_KEY = process.env.ALCHEMY_POLYGON_MUMBAI_KEY || "";
const ALCHEMY_ETH_MAINNET_KEY = process.env.ALCHEMY_ETH_MAINNET_KEY || "";
const ALCHEMY_POLYGON_MAINNET_KEY = process.env.ALCHEMY_POLYGON_MAINNET_KEY || "";

interface ethNetworkConfig {
  [key: string]: NetworkUserConfig;
}
function createNetworkConfig(network: ethNetwork | polygonNetwork, type: "eth" | "polygon" = "eth"): ethNetworkConfig {
  // Use a mainnet key for mainnet, otherwise use a testnet key
  const ALCHEMY_ETH_KEY = network === "mainnet" ? ALCHEMY_ETH_MAINNET_KEY : ALCHEMY_ETH_GOERLI_KEY;
  const ALCHEMY_POLYGON_KEY = network === "mainnet" ? ALCHEMY_POLYGON_MAINNET_KEY : ALCHEMY_POLYGON_MUMBAI_KEY;

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
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10_000,
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

  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  mocha: {
    timeout: 7200000,
  },
  abiExporter: {
    runOnCompile: true,
    path: "./abi",
    clear: true,
    flat: true,
    spacing: 2,
    // We use both Openzeppelin and solmate ERC20, so exporting abi will throw "duplicate output destination" error
    except: [":ERC20$", ":ILendingPoolAddressesProviderRegistry$"],
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
