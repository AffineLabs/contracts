import { ethers } from "hardhat";
import { ERC20__factory } from "../../typechain";

async function testStrategy(): Promise<any> {
  // This only runs on mumbai for now

  const strategy = (await ethers.getContractFactory("L2AAVEStrategy")).attach(
    "0xB41990DD87a34E764a826B95dd50981Dc281425D",
  );
  // make sure the vault has a bit of usdc (aave compatible)
  //   const [gov] = await ethers.getSigners();
  //   const usdc = ERC20__factory.connect("0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e", gov);
  //   await usdc.transfer(await strategy.vault(), ethers.utils.parseUnits("1", 6));

  console.log("strategy balance: ", await strategy.balanceOfAToken());
  console.log("strategy token: ", await strategy.want());
  //   await strategy.harvest();

  // wait for 5 seconds;
  await new Promise(r => setTimeout(r, 5000));

  console.log("strategy balance: ", [await strategy.balanceOfAToken()]);
}

testStrategy()
  .then(() => {
    console.log("Strategy test finished.");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
