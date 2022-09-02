import { getSignedVAA, getEmitterAddressEth, ChainId } from "@certusone/wormhole-sdk";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";
import { BigNumber } from "ethers";
import { sleep } from "./wait-utils";

export async function attemptGettingVAA(
  wormholeAPIURL: string,
  emitter: string,
  sequence: BigNumber,
  emitterChain: ChainId,
) {
  try {
    const result = await getSignedVAA(wormholeAPIURL, emitterChain, getEmitterAddressEth(emitter), String(sequence), {
      transport: NodeHttpTransport(),
    });
    return result.vaaBytes;
  } catch (e) {
    return undefined;
  }
}

export async function getVAA(emitter: string, sequence: string, emitterChain: number, maxAttempts = 64) {
  let result;
  let attempts = 0;
  while (!result) {
    console.log("waiting for VAA");
    attempts += 1;
    await sleep(60000);

    try {
      result = await getSignedVAA(
        "https://wormhole-v2-testnet-api.certus.one",
        emitterChain as ChainId,
        getEmitterAddressEth(emitter),
        sequence,
        {
          transport: NodeHttpTransport(),
        },
      );
    } catch (e) {
      if (attempts > maxAttempts) throw e;
    }
  }
  return result.vaaBytes;
}
