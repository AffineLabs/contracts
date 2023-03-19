import { Contract, providers, utils, ethers } from "ethers";

const TOKEN_CONFIGS = {
  WETH: {
    // https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2?a=0x2f0b23f53734252bda2277357e97e1517d6b042a
    address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    decimals: 18,
    tokenHolder: "0x2f0b23f53734252bda2277357e97e1517d6b042a",
  },
};

type SetBalanceParams = {
  symbol: "WETH";
  amount: string;
  address: string;
  provider: providers.JsonRpcProvider;
};

const setBalance = async ({ symbol, amount, address: tokenReceiver, provider }: SetBalanceParams) => {
  const tokenConfig = TOKEN_CONFIGS[symbol];

  const { address: contractAddress, decimals, tokenHolder } = tokenConfig;

  const contractAbi = [
    // Get the account balance
    "function balanceOf(address) view returns (uint)",

    // Send some of your tokens to someone else
    "function transfer(address to, uint amount)",
  ];
  const contract = new Contract(contractAddress, contractAbi, provider);

  // Fund token holder so they can make the transaction
  await provider.send("hardhat_setBalance", [tokenHolder, utils.parseEther("1.0").toHexString().replace("0x0", "0x")]);

  // Impersonate the token holder
  await provider.send("anvil_impersonateAccount", [tokenHolder]);

  // Get the token holder signer
  const signer = await provider.getSigner(tokenHolder);

  // Connect signed with the contract
  const contractWithSigner = contract.connect(signer);

  // Tranfer funds
  const unitAmount = utils.parseUnits(amount, decimals);
  await contractWithSigner.transfer(tokenReceiver, unitAmount);

  await provider.send("anvil_stopImpersonatingAccount", [tokenHolder]);
};

async function main() {
  const provider = new ethers.providers.JsonRpcProvider();

  await setBalance({
    symbol: "WETH",
    amount: "1000",
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    provider,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
