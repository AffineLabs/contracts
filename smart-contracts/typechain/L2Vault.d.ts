/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import {
  ethers,
  EventFilter,
  Signer,
  BigNumber,
  BigNumberish,
  PopulatedTransaction,
  BaseContract,
  ContractTransaction,
  Overrides,
  CallOverrides,
} from "ethers";
import { BytesLike } from "@ethersproject/bytes";
import { Listener, Provider } from "@ethersproject/providers";
import { FunctionFragment, EventFragment, Result } from "@ethersproject/abi";
import { TypedEventFilter, TypedEvent, TypedListener } from "./commons";

interface L2VaultInterface extends ethers.utils.Interface {
  functions: {
    "L1L2Rebalance()": FunctionFragment;
    "L1TotalLockedValue()": FunctionFragment;
    "MAX_STRATEGIES()": FunctionFragment;
    "addStrategy(address,uint256,uint256,uint256)": FunctionFragment;
    "allowance(address,address)": FunctionFragment;
    "approve(address,uint256)": FunctionFragment;
    "balanceOf(address)": FunctionFragment;
    "creditAvailable(address)": FunctionFragment;
    "debtOutstanding(address)": FunctionFragment;
    "debtRatio()": FunctionFragment;
    "decimals()": FunctionFragment;
    "decreaseAllowance(address,uint256)": FunctionFragment;
    "deposit(address,uint256)": FunctionFragment;
    "globalTVL()": FunctionFragment;
    "governance()": FunctionFragment;
    "increaseAllowance(address,uint256)": FunctionFragment;
    "lastReport()": FunctionFragment;
    "liquidate(uint256)": FunctionFragment;
    "name()": FunctionFragment;
    "rebalance()": FunctionFragment;
    "removeStrategy(address)": FunctionFragment;
    "report(uint256,uint256,uint256)": FunctionFragment;
    "setL1TVL(uint256)": FunctionFragment;
    "symbol()": FunctionFragment;
    "token()": FunctionFragment;
    "totalDebt()": FunctionFragment;
    "totalSupply()": FunctionFragment;
    "transfer(address,uint256)": FunctionFragment;
    "transferFrom(address,address,uint256)": FunctionFragment;
    "updateManyStrategyDebtRatios(address[],uint256[])": FunctionFragment;
    "updateStrategyDebtRatio(address,uint256)": FunctionFragment;
    "vaultTVL()": FunctionFragment;
    "withdraw(address,uint256)": FunctionFragment;
    "withdrawalQueue(uint256)": FunctionFragment;
  };

  encodeFunctionData(
    functionFragment: "L1L2Rebalance",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "L1TotalLockedValue",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "MAX_STRATEGIES",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "addStrategy",
    values: [string, BigNumberish, BigNumberish, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "allowance",
    values: [string, string]
  ): string;
  encodeFunctionData(
    functionFragment: "approve",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "balanceOf", values: [string]): string;
  encodeFunctionData(
    functionFragment: "creditAvailable",
    values: [string]
  ): string;
  encodeFunctionData(
    functionFragment: "debtOutstanding",
    values: [string]
  ): string;
  encodeFunctionData(functionFragment: "debtRatio", values?: undefined): string;
  encodeFunctionData(functionFragment: "decimals", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "decreaseAllowance",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "deposit",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "globalTVL", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "governance",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "increaseAllowance",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "lastReport",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "liquidate",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "name", values?: undefined): string;
  encodeFunctionData(functionFragment: "rebalance", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "removeStrategy",
    values: [string]
  ): string;
  encodeFunctionData(
    functionFragment: "report",
    values: [BigNumberish, BigNumberish, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "setL1TVL",
    values: [BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "symbol", values?: undefined): string;
  encodeFunctionData(functionFragment: "token", values?: undefined): string;
  encodeFunctionData(functionFragment: "totalDebt", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "totalSupply",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "transfer",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "transferFrom",
    values: [string, string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "updateManyStrategyDebtRatios",
    values: [string[], BigNumberish[]]
  ): string;
  encodeFunctionData(
    functionFragment: "updateStrategyDebtRatio",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(functionFragment: "vaultTVL", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "withdraw",
    values: [string, BigNumberish]
  ): string;
  encodeFunctionData(
    functionFragment: "withdrawalQueue",
    values: [BigNumberish]
  ): string;

  decodeFunctionResult(
    functionFragment: "L1L2Rebalance",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "L1TotalLockedValue",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "MAX_STRATEGIES",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "addStrategy",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "allowance", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "approve", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "balanceOf", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "creditAvailable",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "debtOutstanding",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "debtRatio", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "decimals", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "decreaseAllowance",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "deposit", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "globalTVL", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "governance", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "increaseAllowance",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "lastReport", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "liquidate", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "name", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "rebalance", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "removeStrategy",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "report", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "setL1TVL", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "symbol", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "token", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "totalDebt", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "totalSupply",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "transfer", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "transferFrom",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "updateManyStrategyDebtRatios",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "updateStrategyDebtRatio",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "vaultTVL", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "withdraw", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "withdrawalQueue",
    data: BytesLike
  ): Result;

  events: {
    "Approval(address,address,uint256)": EventFragment;
    "Liquidation(uint256,uint256)": EventFragment;
    "StrategyAdded(address,uint256,uint256,uint256)": EventFragment;
    "StrategyRemoved(address)": EventFragment;
    "StrategyReported(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)": EventFragment;
    "StrategyUpdateDebtRatio(address,uint256)": EventFragment;
    "Transfer(address,address,uint256)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "Approval"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "Liquidation"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "StrategyAdded"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "StrategyRemoved"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "StrategyReported"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "StrategyUpdateDebtRatio"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "Transfer"): EventFragment;
}

export class L2Vault extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  listeners<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter?: TypedEventFilter<EventArgsArray, EventArgsObject>
  ): Array<TypedListener<EventArgsArray, EventArgsObject>>;
  off<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this;
  on<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this;
  once<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this;
  removeListener<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this;
  removeAllListeners<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>
  ): this;

  listeners(eventName?: string): Array<Listener>;
  off(eventName: string, listener: Listener): this;
  on(eventName: string, listener: Listener): this;
  once(eventName: string, listener: Listener): this;
  removeListener(eventName: string, listener: Listener): this;
  removeAllListeners(eventName?: string): this;

  queryFilter<EventArgsArray extends Array<any>, EventArgsObject>(
    event: TypedEventFilter<EventArgsArray, EventArgsObject>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TypedEvent<EventArgsArray & EventArgsObject>>>;

  interface: L2VaultInterface;

  functions: {
    L1L2Rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    L1TotalLockedValue(overrides?: CallOverrides): Promise<[BigNumber]>;

    MAX_STRATEGIES(overrides?: CallOverrides): Promise<[number]>;

    addStrategy(
      strategy: string,
      debtRatio_: BigNumberish,
      minDebtPerHarvest: BigNumberish,
      maxDebtPerHarvest: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    allowance(
      owner: string,
      spender: string,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    approve(
      spender: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    balanceOf(account: string, overrides?: CallOverrides): Promise<[BigNumber]>;

    creditAvailable(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    debtOutstanding(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    debtRatio(overrides?: CallOverrides): Promise<[BigNumber]>;

    decimals(overrides?: CallOverrides): Promise<[number]>;

    decreaseAllowance(
      spender: string,
      subtractedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    deposit(
      user: string,
      amountToken: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    globalTVL(overrides?: CallOverrides): Promise<[BigNumber]>;

    governance(overrides?: CallOverrides): Promise<[string]>;

    increaseAllowance(
      spender: string,
      addedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    lastReport(overrides?: CallOverrides): Promise<[BigNumber]>;

    liquidate(
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    name(overrides?: CallOverrides): Promise<[string]>;

    rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    removeStrategy(
      strategy: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    report(
      gain: BigNumberish,
      loss: BigNumberish,
      debtPayment: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    setL1TVL(
      l1TVL: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    symbol(overrides?: CallOverrides): Promise<[string]>;

    token(overrides?: CallOverrides): Promise<[string]>;

    totalDebt(overrides?: CallOverrides): Promise<[BigNumber]>;

    totalSupply(overrides?: CallOverrides): Promise<[BigNumber]>;

    transfer(
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    transferFrom(
      sender: string,
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    updateManyStrategyDebtRatios(
      strategies_: string[],
      debtRatios: BigNumberish[],
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    updateStrategyDebtRatio(
      strategy: string,
      debtRatio_: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    vaultTVL(overrides?: CallOverrides): Promise<[BigNumber]>;

    withdraw(
      user: string,
      shares: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;

    withdrawalQueue(
      arg0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<[string]>;
  };

  L1L2Rebalance(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  L1TotalLockedValue(overrides?: CallOverrides): Promise<BigNumber>;

  MAX_STRATEGIES(overrides?: CallOverrides): Promise<number>;

  addStrategy(
    strategy: string,
    debtRatio_: BigNumberish,
    minDebtPerHarvest: BigNumberish,
    maxDebtPerHarvest: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  allowance(
    owner: string,
    spender: string,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  approve(
    spender: string,
    amount: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  balanceOf(account: string, overrides?: CallOverrides): Promise<BigNumber>;

  creditAvailable(
    strategy: string,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  debtOutstanding(
    strategy: string,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  debtRatio(overrides?: CallOverrides): Promise<BigNumber>;

  decimals(overrides?: CallOverrides): Promise<number>;

  decreaseAllowance(
    spender: string,
    subtractedValue: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  deposit(
    user: string,
    amountToken: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  globalTVL(overrides?: CallOverrides): Promise<BigNumber>;

  governance(overrides?: CallOverrides): Promise<string>;

  increaseAllowance(
    spender: string,
    addedValue: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  lastReport(overrides?: CallOverrides): Promise<BigNumber>;

  liquidate(
    amount: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  name(overrides?: CallOverrides): Promise<string>;

  rebalance(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  removeStrategy(
    strategy: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  report(
    gain: BigNumberish,
    loss: BigNumberish,
    debtPayment: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  setL1TVL(
    l1TVL: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  symbol(overrides?: CallOverrides): Promise<string>;

  token(overrides?: CallOverrides): Promise<string>;

  totalDebt(overrides?: CallOverrides): Promise<BigNumber>;

  totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

  transfer(
    recipient: string,
    amount: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  transferFrom(
    sender: string,
    recipient: string,
    amount: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  updateManyStrategyDebtRatios(
    strategies_: string[],
    debtRatios: BigNumberish[],
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  updateStrategyDebtRatio(
    strategy: string,
    debtRatio_: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  vaultTVL(overrides?: CallOverrides): Promise<BigNumber>;

  withdraw(
    user: string,
    shares: BigNumberish,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;

  withdrawalQueue(
    arg0: BigNumberish,
    overrides?: CallOverrides
  ): Promise<string>;

  callStatic: {
    L1L2Rebalance(overrides?: CallOverrides): Promise<void>;

    L1TotalLockedValue(overrides?: CallOverrides): Promise<BigNumber>;

    MAX_STRATEGIES(overrides?: CallOverrides): Promise<number>;

    addStrategy(
      strategy: string,
      debtRatio_: BigNumberish,
      minDebtPerHarvest: BigNumberish,
      maxDebtPerHarvest: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    allowance(
      owner: string,
      spender: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    approve(
      spender: string,
      amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<boolean>;

    balanceOf(account: string, overrides?: CallOverrides): Promise<BigNumber>;

    creditAvailable(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    debtOutstanding(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    debtRatio(overrides?: CallOverrides): Promise<BigNumber>;

    decimals(overrides?: CallOverrides): Promise<number>;

    decreaseAllowance(
      spender: string,
      subtractedValue: BigNumberish,
      overrides?: CallOverrides
    ): Promise<boolean>;

    deposit(
      user: string,
      amountToken: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    globalTVL(overrides?: CallOverrides): Promise<BigNumber>;

    governance(overrides?: CallOverrides): Promise<string>;

    increaseAllowance(
      spender: string,
      addedValue: BigNumberish,
      overrides?: CallOverrides
    ): Promise<boolean>;

    lastReport(overrides?: CallOverrides): Promise<BigNumber>;

    liquidate(amount: BigNumberish, overrides?: CallOverrides): Promise<void>;

    name(overrides?: CallOverrides): Promise<string>;

    rebalance(overrides?: CallOverrides): Promise<void>;

    removeStrategy(strategy: string, overrides?: CallOverrides): Promise<void>;

    report(
      gain: BigNumberish,
      loss: BigNumberish,
      debtPayment: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    setL1TVL(l1TVL: BigNumberish, overrides?: CallOverrides): Promise<void>;

    symbol(overrides?: CallOverrides): Promise<string>;

    token(overrides?: CallOverrides): Promise<string>;

    totalDebt(overrides?: CallOverrides): Promise<BigNumber>;

    totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

    transfer(
      recipient: string,
      amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<boolean>;

    transferFrom(
      sender: string,
      recipient: string,
      amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<boolean>;

    updateManyStrategyDebtRatios(
      strategies_: string[],
      debtRatios: BigNumberish[],
      overrides?: CallOverrides
    ): Promise<void>;

    updateStrategyDebtRatio(
      strategy: string,
      debtRatio_: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    vaultTVL(overrides?: CallOverrides): Promise<BigNumber>;

    withdraw(
      user: string,
      shares: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>;

    withdrawalQueue(
      arg0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<string>;
  };

  filters: {
    Approval(
      owner?: string | null,
      spender?: string | null,
      value?: null
    ): TypedEventFilter<
      [string, string, BigNumber],
      { owner: string; spender: string; value: BigNumber }
    >;

    Liquidation(
      amountRequested?: null,
      amountLiquidated?: null
    ): TypedEventFilter<
      [BigNumber, BigNumber],
      { amountRequested: BigNumber; amountLiquidated: BigNumber }
    >;

    StrategyAdded(
      strategy?: string | null,
      debtRatio?: null,
      minDebtPerHarvest?: null,
      maxDebtPerHarvest?: null
    ): TypedEventFilter<
      [string, BigNumber, BigNumber, BigNumber],
      {
        strategy: string;
        debtRatio: BigNumber;
        minDebtPerHarvest: BigNumber;
        maxDebtPerHarvest: BigNumber;
      }
    >;

    StrategyRemoved(
      strategy?: string | null
    ): TypedEventFilter<[string], { strategy: string }>;

    StrategyReported(
      strategy?: string | null,
      gain?: null,
      loss?: null,
      debtPaid?: null,
      totalGain?: null,
      totalLoss?: null,
      totalDebt?: null,
      debtAdded?: null,
      debtRatio?: null
    ): TypedEventFilter<
      [
        string,
        BigNumber,
        BigNumber,
        BigNumber,
        BigNumber,
        BigNumber,
        BigNumber,
        BigNumber,
        BigNumber
      ],
      {
        strategy: string;
        gain: BigNumber;
        loss: BigNumber;
        debtPaid: BigNumber;
        totalGain: BigNumber;
        totalLoss: BigNumber;
        totalDebt: BigNumber;
        debtAdded: BigNumber;
        debtRatio: BigNumber;
      }
    >;

    StrategyUpdateDebtRatio(
      strategy?: string | null,
      debtRatio?: null
    ): TypedEventFilter<
      [string, BigNumber],
      { strategy: string; debtRatio: BigNumber }
    >;

    Transfer(
      from?: string | null,
      to?: string | null,
      value?: null
    ): TypedEventFilter<
      [string, string, BigNumber],
      { from: string; to: string; value: BigNumber }
    >;
  };

  estimateGas: {
    L1L2Rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    L1TotalLockedValue(overrides?: CallOverrides): Promise<BigNumber>;

    MAX_STRATEGIES(overrides?: CallOverrides): Promise<BigNumber>;

    addStrategy(
      strategy: string,
      debtRatio_: BigNumberish,
      minDebtPerHarvest: BigNumberish,
      maxDebtPerHarvest: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    allowance(
      owner: string,
      spender: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    approve(
      spender: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    balanceOf(account: string, overrides?: CallOverrides): Promise<BigNumber>;

    creditAvailable(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    debtOutstanding(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    debtRatio(overrides?: CallOverrides): Promise<BigNumber>;

    decimals(overrides?: CallOverrides): Promise<BigNumber>;

    decreaseAllowance(
      spender: string,
      subtractedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    deposit(
      user: string,
      amountToken: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    globalTVL(overrides?: CallOverrides): Promise<BigNumber>;

    governance(overrides?: CallOverrides): Promise<BigNumber>;

    increaseAllowance(
      spender: string,
      addedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    lastReport(overrides?: CallOverrides): Promise<BigNumber>;

    liquidate(
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    name(overrides?: CallOverrides): Promise<BigNumber>;

    rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    removeStrategy(
      strategy: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    report(
      gain: BigNumberish,
      loss: BigNumberish,
      debtPayment: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    setL1TVL(
      l1TVL: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    symbol(overrides?: CallOverrides): Promise<BigNumber>;

    token(overrides?: CallOverrides): Promise<BigNumber>;

    totalDebt(overrides?: CallOverrides): Promise<BigNumber>;

    totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

    transfer(
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    transferFrom(
      sender: string,
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    updateManyStrategyDebtRatios(
      strategies_: string[],
      debtRatios: BigNumberish[],
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    updateStrategyDebtRatio(
      strategy: string,
      debtRatio_: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    vaultTVL(overrides?: CallOverrides): Promise<BigNumber>;

    withdraw(
      user: string,
      shares: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>;

    withdrawalQueue(
      arg0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    L1L2Rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    L1TotalLockedValue(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    MAX_STRATEGIES(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    addStrategy(
      strategy: string,
      debtRatio_: BigNumberish,
      minDebtPerHarvest: BigNumberish,
      maxDebtPerHarvest: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    allowance(
      owner: string,
      spender: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    approve(
      spender: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    balanceOf(
      account: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    creditAvailable(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    debtOutstanding(
      strategy: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    debtRatio(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    decimals(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    decreaseAllowance(
      spender: string,
      subtractedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    deposit(
      user: string,
      amountToken: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    globalTVL(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    governance(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    increaseAllowance(
      spender: string,
      addedValue: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    lastReport(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    liquidate(
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    name(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    rebalance(
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    removeStrategy(
      strategy: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    report(
      gain: BigNumberish,
      loss: BigNumberish,
      debtPayment: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    setL1TVL(
      l1TVL: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    symbol(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    token(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    totalDebt(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    totalSupply(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    transfer(
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    transferFrom(
      sender: string,
      recipient: string,
      amount: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    updateManyStrategyDebtRatios(
      strategies_: string[],
      debtRatios: BigNumberish[],
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    updateStrategyDebtRatio(
      strategy: string,
      debtRatio_: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    vaultTVL(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    withdraw(
      user: string,
      shares: BigNumberish,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>;

    withdrawalQueue(
      arg0: BigNumberish,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;
  };
}
