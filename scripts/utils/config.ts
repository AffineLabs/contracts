import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { address } from "./types";

dotenvConfig({ path: resolve(__dirname, "./.env") });

export interface l1Config {
  chainManager: address;
  ERC20Predicate: address;
  usdc: address;
  wormhole: address;
  create2Deployer: address;
  governance: address;
  compound: {
    cToken: address;
    comptroller: address;
    uniRouter: address;
    rewardToken: address;
    wrappedNative: address;
  };
}
export interface l2Config {
  governance: address;
  usdc: address;
  wormhole: address;
  create2Deployer: address;
  weth: address;
  wbtc: address;
  feeds: {
    usdc: address;
    wbtc: address;
    weth: address;
  };
  withdrawFee: number;
  managementFee: number;
  aave: {
    registry: address;
    incentivesController: address;
    uniRouter: address;
    rewardToken: address;
    wrappedNative: address;
  };
}

export interface totalConfig {
  mainnet: boolean;
  l1: l1Config;
  l2: l2Config;
}

export const testConfig: totalConfig = {
  mainnet: false,
  l1: {
    governance: "0xdbA49884464689800BF95C7BbD50eBA0DA0F67b9",
    usdc: "0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3",
    wormhole: "0x706abc4E45D419950511e474C7B9Ed348A4a716c",
    create2Deployer: "0x7F4eD93f8Da2A07008de3f87759d220e2f7B8C40", // Testnet create2 deployer contract deployed by Affine
    chainManager: "0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74",
    ERC20Predicate: "0x37c3bfC05d5ebF9EBb3FF80ce0bd0133Bf221BC8",
    compound: {
      cToken: "",
      comptroller: "",
      uniRouter: "",
      rewardToken: "",
      wrappedNative: "",
    },
  },
  l2: {
    // See https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deployment for more addresses
    usdc: "0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538",
    wormhole: "0x0CBE91CF822c73C2315FB05100C2F714765d5c20",
    create2Deployer: "0x7F4eD93f8Da2A07008de3f87759d220e2f7B8C40",
    governance: "0xCBF0C1bA68D22666ef01069b1a42CcC1F0281A9C",
    withdrawFee: 50,
    managementFee: 200,
    wbtc: "0xc8BA1fdaf17c1f16C68778fde5f78F3D37cD1509",
    weth: "0x3dd7F3CF122e0460Dba8A75d191b3486752B6A61",
    feeds: {
      usdc: "0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0",
      wbtc: "0x007A22900a3B98143368Bd5906f8E17e9867581b",
      weth: "0x0715A7794a1dc8e42615F059dD6e406A6594651A",
    },
    aave: {
      registry: "",
      incentivesController: "",
      uniRouter: "",
      rewardToken: "",
      wrappedNative: "",
    },
  },
};

export const mainnetConfig: totalConfig = {
  mainnet: true,
  l1: {
    chainManager: "0xA0c68C638235ee32657e8f720a23ceC1bFc77C77",
    ERC20Predicate: "0x9923263fA127b3d1484cFD649df8f1831c2A74e4",
    usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    wormhole: "0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B",
    create2Deployer: "0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2", // warning: This can be paused by the owner
    governance: "0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e",
    compound: {
      cToken: "0x39AA39c021dfbaE8faC545936693aC917d5E7563",
      comptroller: "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B",
      uniRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // uniswap v2
      rewardToken: "0xc00e94Cb662C3520282E6f5717214004A7f26888", // comp
      wrappedNative: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    },
  },
  l2: {
    // See https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/deployment for more addresses
    usdc: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
    wormhole: "0x0CBE91CF822c73C2315FB05100C2F714765d5c20",
    create2Deployer: "0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2",
    governance: "0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0",
    withdrawFee: 0,
    managementFee: 0,
    wbtc: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6",
    weth: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
    feeds: {
      usdc: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7",
      wbtc: "0xc907E116054Ad103354f2D350FD2514433D57F6f",
      weth: "0xF9680D99D6C9589e2a93a78A04A279e509205945",
    },
    aave: {
      registry: "0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19",
      incentivesController: "0x357D51124f59836DeD84c8a1730D72B749d8BC23",
      uniRouter: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
      rewardToken: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
      wrappedNative: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    },
  },
};
