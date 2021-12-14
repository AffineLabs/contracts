import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { getSignedVAA, getEmitterAddressEth } from "@certusone/wormhole-sdk";
import { DummyBridge__factory } from "../typechain/factories/DummyBridge__factory";
import { DummyReceiver__factory } from "../typechain/factories/DummyReceiver__factory";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";

dotenvConfig({ path: resolve(__dirname, "./.env") });

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function deployDummy(): Promise<any> {
  const [deployer] = await ethers.getSigners();
  const factory = new DummyBridge__factory(deployer);
  // deploy dummy bridge
  const bridge = await factory.deploy("0x706abc4E45D419950511e474C7B9Ed348A4a716c", 400);
  await bridge.deployed();

  console.log("bridge deployed at: ", bridge.address);

  const rFactory = new DummyReceiver__factory(deployer);
  // deploy receiver
  const rec = await rFactory.deploy("0x706abc4E45D419950511e474C7B9Ed348A4a716c");
  await rec.deployed();

  // send tvl message
  const tx = await bridge.sendTVL();
  await tx.wait();
  console.log("tvl updated");

  let result;
  let attempts = 0;
  const maxAttempts = 60;
  while (!result) {
    console.log("waiting");
    attempts += 1;
    await sleep(1000);
    // get signed vaa

    try {
      result = await getSignedVAA(
        "https://wormhole-v2-testnet-api.certus.one",
        2,
        getEmitterAddressEth(bridge.address),
        ((await bridge.nonce()) - 1).toString(),
        {
          transport: NodeHttpTransport(),
        },
      );
    } catch (e) {
      if (attempts > maxAttempts) throw e;
    }
  }
  console.log({ result });

  // send vaa to receiver contract (this contract will be on another chain in prod)
  const vaaTx = await rec.receiveMessage(result.vaaBytes);
  await vaaTx.wait();

  console.log("received tvl: ", await rec.tvl());
}

deployDummy()
  .then(() => {
    console.log("Dummy deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
