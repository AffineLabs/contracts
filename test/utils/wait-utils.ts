import axios from "axios";

import { ethers } from "ethers";
import { BigNumber, Contract } from "ethers";
import { address } from "../../utils/types";

export async function sleep(ms: number) {
  await new Promise(f => setTimeout(f, ms));
}

export async function waitForL2MessageProof(maticAPIUrl: string, txHash: string, eventSig: string): Promise<string> {
  const url = `${maticAPIUrl}/exit-payload/${txHash}?eventSignature=${eventSig}`;
  console.log(`Waiting for message proof by polling URL: ${url}\n`);
  const startTime = new Date().getTime();
  while (true) {
    await sleep(60000);
    type MaticAPIResponse = {
      error: boolean;
      message: string;
      result: string;
    };
    try {
      const resp = await axios.get<MaticAPIResponse>(url);
      const proofObj = resp.data;
      if ("result" in proofObj && !("error" in proofObj)) {
        return proofObj.result;
      }
    } catch (err) {
      if (!axios.isAxiosError(err)) {
        throw err;
      }
    }
    const nowTime = new Date().getTime();
    console.log(
      "Still waiting for message to be checkpointed from L2 -> L1.",
      `Elapsed time: ${(nowTime - startTime) * 0.001}s`,
    );
  }
}

export async function waitForNonZeroAddressTokenBalance(
  tokenAddres: address,
  tokenABI: any,
  indentifier: string,
  userAddress: address,
  provider: ethers.providers.Provider,
) {
  const polygonUSDCContract: Contract = new ethers.Contract(tokenAddres, tokenABI, provider);
  const startTime = new Date().getTime();
  while (true) {
    await sleep(60000);
    const stagingBalance: BigNumber = await polygonUSDCContract.balanceOf(userAddress);
    if (!stagingBalance.isZero()) {
      break;
    }
    const nowTime = new Date().getTime();
    console.log(
      `Still waiting for fund to be reflected in ${indentifier} address.`,
      `Elapsed time: ${(nowTime - startTime) * 0.001}s`,
    );
  }
}
