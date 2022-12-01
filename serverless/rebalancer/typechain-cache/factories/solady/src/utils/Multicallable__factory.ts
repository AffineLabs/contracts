/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type {
  Multicallable,
  MulticallableInterface,
} from "../../../../solady/src/utils/Multicallable";

const _abi = [
  {
    inputs: [
      {
        internalType: "bytes[]",
        name: "data",
        type: "bytes[]",
      },
    ],
    name: "multicall",
    outputs: [
      {
        internalType: "bytes[]",
        name: "results",
        type: "bytes[]",
      },
    ],
    stateMutability: "payable",
    type: "function",
  },
];

export class Multicallable__factory {
  static readonly abi = _abi;
  static createInterface(): MulticallableInterface {
    return new utils.Interface(_abi) as MulticallableInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): Multicallable {
    return new Contract(address, _abi, signerOrProvider) as Multicallable;
  }
}
