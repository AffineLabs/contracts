# Liquidate Affine vault strategies → base asset

Governance transactions that pull all funds out of each vault's strategies back into the
vault as idle `asset`, so users can withdraw without triggering per-withdrawal protocol
redemption (Aave / Stader leverage unwind / Convex+Curve LP exit).

## Mechanism

Each vault is an `AffineVault`. The only governance-gated liquidation lever is:

```solidity
function removeStrategy(address strategy) external onlyGovernance;
// -> _withdrawFromStrategy(strategy, strategy.totalLockedValue())  (divest ALL to vault)
// -> isActive = false, tvlBps = 0, removed from withdrawalQueue
```

`governance` on every vault is an OpenZeppelin `TimelockController`. The 2/N Gnosis Safe holds
`PROPOSER_ROLE`; the executor role is open (`address(0)`), so anyone can execute after the delay.

Flow per strategy:

```
Safe --schedule(vault,0,removeStrategyCalldata,0x0,salt,delay)--> Timelock
   --(wait minDelay)--> execute(vault,0,removeStrategyCalldata,0x0,salt) --> vault.removeStrategy()
```

`predecessor = 0x0`. `schedule` and `execute` MUST use the same `salt` (baked into the files).

## Contracts

| Vault | Chain | Vault addr | Timelock (governance) | Delay | Strategy removed |
|---|---|---|---|---|---|
| USDC.e USD Earn | Polygon (137) | `0x829363736a5A9080e05549Db6d1271f070a7e224` | `0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0` | 1s | AaveV3 `0x4201e68E165615caBC62209f30e2545B32F8e01a`; old Aave `0x626db3135BDe0b194fb1570E2008846681DeAE30` |
| Stader leverage-MATIC | Polygon (137) | `0x5cfD50De188a36d2089927c5a14E143DC65Af780` | `0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0` | 1s | StaderLevMatic `0x8bB3C906F6E759866804fCb290a3987c0ccc6AeC` |
| Convex LP | Ethereum (1) | `0x78Bb94Feab383ccEd39766a7d6CF31dED177Ad0c` | `0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e` | 24h | Convex `0x4969592B0C5A6e6827beED275fe644B2eCD3b0F3` |

Proposer Safe (Ethereum): `0x67ec3bb25a5db6eb7ba74f6c0b2ba193a3983fb8` (2/4). Verify the Polygon
timelock's proposer before scheduling there.

## Files (Safe → Transaction Builder → Import)

1. `safe_batch_SCHEDULE_chain137.json` — schedules removal of all 3 Polygon strategies
2. `safe_batch_EXECUTE_chain137.json`  — executes them (send in a LATER block than schedule)
3. `safe_batch_SCHEDULE_chain1.json`   — schedules Convex removal (Ethereum)
4. `safe_batch_EXECUTE_chain1.json`    — executes it (send after 24h)

Polygon delay is 1s, so execute cannot be in the same block/batch as schedule — run the
EXECUTE batch a few seconds after the SCHEDULE batch confirms.

## Before signing

1. **Convex accounting**: live `totalLockedValue()` (~$314) << vault recorded balance (~$2,237).
   Run `harvest([0x4969...b0F3])` first to claim rewards + book P&L, then investigate the gap;
   `removeStrategy` only divests the live TLV (it also reconciles balances, but harvest lets you
   see the realized loss before you sign the removal). See `harvest_convex.json`. HARVESTER is
   held by keeper EOA `0x47fd0834...0946d` (instant direct call) and by the timelock
   `0x4B21...a56e` (24h governance route).
2. **Stader `slippageBps`**: removal unwinds Aave leverage with slippage — confirm
   `slippageBps()` on `0x8bB3...6AeC` is sane first.
3. **Roles**: confirm the signing Safe holds `PROPOSER_ROLE` on the Polygon timelock.
   (Confirmed on-chain: Polygon Safe `0x47c43be6…fc00fb` and ETH Safe `0x67ec3bb2…3983fb8`
   both hold `PROPOSER_ROLE`; executor role is open.)

## Status

As of last check, the three Polygon operations are **scheduled and ready** on the timelock
(`isOperationReady == true`) — the EXECUTE batch (`safe_batch_EXECUTE_chain137.json`) can be
submitted now. The Ethereum Convex op still needs scheduling (24h delay).

## Order of operations (IMPORTANT)

`execute` only runs an operation that was already `schedule`d and whose delay has elapsed.
Running the EXECUTE batch first reverts with `TimelockController: operation is not ready`
(surfaced by the Safe as `GS013`). Always:

1. Submit the **SCHEDULE** batch.
2. Wait `>= minDelay` (Polygon 1s → next block; Ethereum 24h).
3. Submit the **EXECUTE** batch.

**Simulating on Tenderly:** a standalone EXECUTE sim always fails (nothing scheduled in live
state). Use a Simulation Bundle [schedule, execute] and, because Polygon `minDelay = 1s`,
override the execute tx's block timestamp to `+2s` — otherwise `isOperationReady` is false.

## Operation IDs (for tracking on the timelock)

Computed as `keccak256(abi.encode(target, 0, data, 0x0, salt))` — matches OZ `hashOperation`.

- USDC.e AaveV3: `0x1d1c08fc586f20c7cd37cbdc9ab9cb1ab8d8a48b33bb0b961d1b5daeed996032`
- USDC.e old Aave: `0x4d85fc4e0556c11ef80dee40363e39991f4802cea0d6344ba029cfbce57fb90c`
- Stader-MATIC: `0x2a550da7513bf4b2aa24ab1ac551a60c25f9c896b594095be51078b227a6d4ab`
- Convex: `0x8abc91bfd74e43714f8d63f2f5daf18a70a1ddddc150be9befa3b6ed62ae8af7`
