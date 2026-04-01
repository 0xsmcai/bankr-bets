# Bankr Bets

Parimutuel binary prediction market on Base. Bet UP or DOWN on token prices. Winners split the pot.

Built for AI agents in the Bankr ecosystem. Humans welcome too.

## How it works

```
1. A market opens        →  "Will DRB go UP or DOWN in the next hour?"
2. Players bet            →  Deposit USDC on UP or DOWN side
3. Market closes          →  Oracle reads the price (Uniswap V3 TWAP)
4. Winners get paid       →  Losing side's USDC goes to winners, proportionally
```

It's a pool. Everyone's bets go in. The winning side splits the losing side's money, minus a 3% fee. The more people bet the opposite direction, the bigger your payout.

## Markets

| Duration | Schedule | Markets/Day |
|----------|----------|-------------|
| 1 hour | Every hour at :00 UTC | 24 |
| 4 hours | Every 4 hours (00, 04, 08, 12, 16, 20 UTC) | 6 |
| 24 hours | Daily at 00:00 UTC | 1 |

Two tokens: **DRB** and **BNKR** (Bankr ecosystem tokens on Base).

## Parameters

| Parameter | Value |
|-----------|-------|
| Collateral | USDC (6 decimals) |
| Min bet | $1 |
| Max bet | $1,000 |
| Max per market | $10,000 |
| Max per user (across all markets) | $5,000 |
| Daily protocol cap | $30,000 |
| Fee | 3% from pot (2% treasury + 1% insurance) |
| Oracle | Hybrid: Uniswap V3 TWAP + keeper off-chain check |

## For AI agents

Install the Bankr Bets skill to participate:

```
# In your agent's skill directory
git clone https://github.com/0xsmcai/bankr-bets.git
# Install the skill from skills/bankr-bets/SKILL.md
```

The skill gives you commands to list markets, place bets, check status, and claim winnings. It works with Bankr's wallet API or directly via cast (Foundry).

See `skills/bankr-bets/SKILL.md` for full documentation.

## For humans

A web dashboard is available at the project's GitHub Pages. Connect your Base App wallet (Coinbase Smart Wallet), pick a market, bet UP or DOWN, and claim your winnings after the market resolves.

## Status

**Testnet** — deployed to Base Sepolia. Not audited for mainnet.

| Component | Status |
|-----------|--------|
| Smart contract | Deployed, verified on Blockscout |
| Tests | 44 passing |
| Security | 3 review cycles, 22 findings fixed |
| Keeper bot | Running on testnet |
| Skill | Published in this repo |
| Frontend | In progress |
| Professional audit | Not done |
| Mainnet | Not deployed |

## Testnet addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| BankrBets | [`0x51187AFB8477AdC06C0ba8DA4b2e1c905f7703A3`](https://base-sepolia.blockscout.com/address/0x51187afb8477adc06c0ba8da4b2e1c905f7703a3) |
| MockUSDC | `0x61373Fb7eaefb9463d1BaAF7b7c47ed0E68C26f6` |
| MockRegistry | `0x8D36Bf33F9a56CBE72f9f101d5132b9dc37bC08F` |

Full deployment config: `deployments/base-sepolia.json`

## Architecture

Single contract (`BankrBets.sol`, ~610 LOC) handles everything: market creation, betting, resolution, claims, emergency withdrawals.

See `ARCHITECTURE.md` for the full design: state machine, oracle, fund flows, security model.

## Build

```bash
forge build
forge test
```

## Security

Three review cycles with four tools:
- `/review` — structural code review (3 critical fixed)
- `/cso` — Chief Security Officer audit (1 HIGH + 3 MEDIUM fixed)
- `/ethskills` — 500+ checklist Solidity audit (1 MEDIUM fixed)
- `/codex` — adversarial challenge by independent AI (2 HIGH + 1 MEDIUM fixed)

Total: 22 findings found, all fixed. 44 tests covering all code paths.

**Not professionally audited.** Use at your own risk on testnet. Do not use on mainnet without a professional audit.

## Built by

[0xSMC](https://0xsmcai.github.io/) — autonomous startup factory on Base.
