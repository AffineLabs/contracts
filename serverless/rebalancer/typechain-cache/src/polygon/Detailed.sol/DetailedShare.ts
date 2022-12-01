/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BigNumberish,
  BytesLike,
  CallOverrides,
  ContractTransaction,
  Overrides,
  PopulatedTransaction,
  Signer,
  utils,
} from "ethers";
import type { FunctionFragment, Result } from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
  PromiseOrValue,
} from "../../../common";

export declare namespace DetailedShare {
  export type NumberStruct = {
    num: PromiseOrValue<BigNumberish>;
    decimals: PromiseOrValue<BigNumberish>;
  };

  export type NumberStructOutput = [BigNumber, number] & {
    num: BigNumber;
    decimals: number;
  };
}

export interface DetailedShareInterface extends utils.Interface {
  functions: {
    "detailedPrice()": FunctionFragment;
    "detailedTVL()": FunctionFragment;
    "detailedTotalSupply()": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "detailedPrice"
      | "detailedTVL"
      | "detailedTotalSupply"
  ): FunctionFragment;

  encodeFunctionData(
    functionFragment: "detailedPrice",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "detailedTVL",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "detailedTotalSupply",
    values?: undefined
  ): string;

  decodeFunctionResult(
    functionFragment: "detailedPrice",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "detailedTVL",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "detailedTotalSupply",
    data: BytesLike
  ): Result;

  events: {};
}

export interface DetailedShare extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: DetailedShareInterface;

  queryFilter<TEvent extends TypedEvent>(
    event: TypedEventFilter<TEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TEvent>>;

  listeners<TEvent extends TypedEvent>(
    eventFilter?: TypedEventFilter<TEvent>
  ): Array<TypedListener<TEvent>>;
  listeners(eventName?: string): Array<Listener>;
  removeAllListeners<TEvent extends TypedEvent>(
    eventFilter: TypedEventFilter<TEvent>
  ): this;
  removeAllListeners(eventName?: string): this;
  off: OnEvent<this>;
  on: OnEvent<this>;
  once: OnEvent<this>;
  removeListener: OnEvent<this>;

  functions: {
    detailedPrice(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    detailedTVL(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    detailedTotalSupply(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;
  };

  detailedPrice(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  detailedTVL(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  detailedTotalSupply(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  callStatic: {
    detailedPrice(
      overrides?: CallOverrides
    ): Promise<DetailedShare.NumberStructOutput>;

    detailedTVL(
      overrides?: CallOverrides
    ): Promise<DetailedShare.NumberStructOutput>;

    detailedTotalSupply(
      overrides?: CallOverrides
    ): Promise<DetailedShare.NumberStructOutput>;
  };

  filters: {};

  estimateGas: {
    detailedPrice(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    detailedTVL(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    detailedTotalSupply(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    detailedPrice(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    detailedTVL(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    detailedTotalSupply(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;
  };
}
