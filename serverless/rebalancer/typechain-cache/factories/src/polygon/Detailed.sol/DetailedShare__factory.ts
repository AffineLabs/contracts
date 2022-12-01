/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type {
  DetailedShare,
  DetailedShareInterface,
} from "../../../../src/polygon/Detailed.sol/DetailedShare";

const _abi = [
  {
    inputs: [],
    name: "detailedPrice",
    outputs: [
      {
        components: [
          {
            internalType: "uint256",
            name: "num",
            type: "uint256",
          },
          {
            internalType: "uint8",
            name: "decimals",
            type: "uint8",
          },
        ],
        internalType: "struct DetailedShare.Number",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "detailedTVL",
    outputs: [
      {
        components: [
          {
            internalType: "uint256",
            name: "num",
            type: "uint256",
          },
          {
            internalType: "uint8",
            name: "decimals",
            type: "uint8",
          },
        ],
        internalType: "struct DetailedShare.Number",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "detailedTotalSupply",
    outputs: [
      {
        components: [
          {
            internalType: "uint256",
            name: "num",
            type: "uint256",
          },
          {
            internalType: "uint8",
            name: "decimals",
            type: "uint8",
          },
        ],
        internalType: "struct DetailedShare.Number",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];

export class DetailedShare__factory {
  static readonly abi = _abi;
  static createInterface(): DetailedShareInterface {
    return new utils.Interface(_abi) as DetailedShareInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): DetailedShare {
    return new Contract(address, _abi, signerOrProvider) as DetailedShare;
  }
}
