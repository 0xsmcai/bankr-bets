# Architecture

## Overview

One smart contract, one keeper bot, one frontend. No proxy, no factory, no multi-contract system.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Agents    │────►│              │◄────│   Humans    │
│ (via skill) │     │  BankrBets   │     │ (via UI)    │
└─────────────┘     │   .sol       │     └─────────────┘
                    │              │
┌─────────────┐     │  Single      │     ┌─────────────┐
│   Keeper    │────►│  Contract    │◄────│  Uniswap V3 │
│   Bot       │     │  on Base     │     │  TWAP Oracle│
└─────────────┘     └──────────────┘     └─────────────┘
```

## Contract: BankrBets.sol

~610 lines of Solidity. Inherits from OpenZeppelin v5.1+:
- `Ownable2Step` — two-step admin transfer (prevents accidental loss of control)
- `ReentrancyGuardTransient` — cheap reentrancy protection via EIP-1153 transient storage
- `Pausable` — emergency stop

### State machine

```
         createMarket()
              │
              ▼
         ┌─────────┐     bet()        ┌──────────┐
         │ PENDING  │◄───────────────►│  Users    │
         │ (open)   │     (USDC in)    │  betting  │
         └────┬─────┘                  └──────────┘
              │
              │  bettingDeadline passes
              │  (15min/30min/60min before close)
              │
              ▼
         ┌─────────┐
         │ LOCKED   │  No more bets accepted
         │ (closed) │
         └────┬─────┘
              │
    ┌─────────┼──────────┐
    │         │          │
    ▼         ▼          ▼
┌───────┐ ┌───────┐ ┌────────┐
│  UP   │ │ DOWN  │ │ VOIDED │
│ wins  │ │ wins  │ │ refund │
└───┬───┘ └───┬───┘ └───┬────┘
    │         │          │
    ▼         ▼          ▼
  claim()   claim()   claim()
  (payout)  (payout)  (deposit back)
```

Markets are VOIDED when:
- Price doesn't move (closing tick == opening tick)
- Minimum participation not met ($100 total, $50/side, 2 players)
- Oracle divergence between TWAP and keeper's off-chain check
- Market not resolved within 4 hours of close (MAX_RESOLUTION_DELAY)
- Admin calls voidMarket() (emergency)

### Hybrid oracle

The contract uses two price sources that must agree:

1. **TWAP** (on-chain): reads `pool.observe()` on the Uniswap V3 pool. 15-minute window for 1h markets, 30-minute for 4h, 60-minute for 24h. Resistant to single-block manipulation.

2. **Keeper tick** (off-chain): the keeper reads the current pool tick via RPC and submits it alongside the resolve() call. The contract compares: if TWAP and keeper diverge by more than 2000 ticks (~22%), it reverts.

If the keeper goes down, anyone can call `resolveByTwap()` after a 2-hour grace period (TWAP-only, no off-chain check). If neither resolves within 4 hours, users can emergency withdraw.

### TWAP windows

| Market duration | Opening TWAP | Closing TWAP | Betting closes |
|-----------------|-------------|-------------|----------------|
| 1 hour | 5 min | 15 min | T-15min |
| 4 hours | 10 min | 30 min | T-30min |
| 24 hours | 30 min | 60 min | T-60min |

Betting closes BEFORE the TWAP window begins. This prevents anyone from observing the price trend and betting on the known outcome.

### Fund flow

```
USDC IN (bet):
  User → safeTransferFrom → Contract balance
  Tracked via: market.totalUp, market.totalDown, market.totalPool

USDC OUT (claim, winner):
  payout = mulDiv(totalPool * 97%, userBet, totalWinningSide)
  Contract → safeTransfer → User

USDC OUT (claim, loser):
  payout = 0 (clears userExposure only)

USDC OUT (claim, voided):
  payout = original deposit (full refund, no fees)

USDC OUT (fees):
  distributeFees() → 2% to treasury, 1% to insurance
  Only callable once per market (feesDistributed guard)

USDC OUT (emergency):
  emergencyWithdraw() → original deposit
  Only after MAX_RESOLUTION_DELAY or voidMarket()
  Voids entire market on first call
```

All transfers use OpenZeppelin's SafeERC20. All payout math uses Math.mulDiv (512-bit precision, rounds down — dust stays in contract).

### Agent tagging

Every bet checks the ERC-8004 Identity Registry via try/catch. If the bettor's address is registered, the `BetPlaced` event includes `isAgent=true`. This powers the agent vs human leaderboard without affecting payouts or access.

## Keeper bot

TypeScript + viem. Runs on a 60-second loop.

- Creates 1h markets every hour, 4h every 4 hours, 24h daily
- Resolves expired markets by reading pool tick (off-chain check) and calling resolve()
- Uses the deploy wallet as both keeper and admin

Located at `keeper/index.ts`. Run with `KEEPER_KEY=0x... npx tsx keeper/index.ts`.

## Frontend

Next.js + wagmi v2 + viem. Reads contract state directly from Base RPC. No backend.

- Coinbase Smart Wallet (Base App) as primary wallet connector
- Polls every 2 seconds (Base block time)
- Design follows DESIGN.md (0xSMC visual system)

## Security model

- 5 functions touch funds (bet, claim, emergencyWithdraw, distributeFees × 2 transfers)
- All use SafeERC20 + ReentrancyGuardTransient
- Internal accounting only (never reads balanceOf)
- Minimum bet of 1 USDC prevents dust attacks
- Emergency withdrawal voids entire market (prevents partial-withdrawal insolvency)
- Emergency withdrawal only available past MAX_RESOLUTION_DELAY (prevents race with resolution)
- Market struct snapshots pool + isToken0 at creation (prevents admin config change attack)
- 3 review cycles, 22 findings fixed, 44 tests
