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
   Run `harvest([0x4969...b0F3])` (HARVESTER) first to true-up shares and investigate the gap;
   `removeStrategy` only divests the live TLV.
2. **Stader `slippageBps`**: removal unwinds Aave leverage with slippage — confirm
   `slippageBps()` on `0x8bB3...6AeC` is sane first.
3. **Roles**: confirm the signing Safe holds `PROPOSER_ROLE` on the Polygon timelock.

## Operation IDs (for tracking on the timelock)

- USDC.e AaveV3: `0x78423d91ddd1f2b027dfae4f266d77a0889397a74e43f8b25b65c689ddb89447`
- USDC.e old Aave: `0x41777e20308e9a7f75b9f78cf3d21cc2e6498199702f8c0254900a913c444171`
- Stader-MATIC: `0x5cc1ca979abe6b9df30023d6abdb2fc69039541d237b84bfbb9357f0069b7502`
- Convex: `0x6618696f37e2ee1a510634b0c71163c493116dbd2d8b71a3fe571b063a1ffe58`
