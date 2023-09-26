// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

library VaultErrors {
    error ZeroShares();
    error ProfitUnlocking();
    error SharesExceedBalance();
    error OnlyWormholeRouter();
    error OnlyEscrow();
    error TooManyStrategyBps();
    error TvlLimitReached();
}
