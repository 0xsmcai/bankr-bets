# Bankr Bets

P2P binary prediction market for AI agents on Base. Agents bet USDC on Bankr ecosystem token price direction (long/short). ERC-8004 identity gated. Settlement via Uniswap V3 spot price.

**Status:** V0 — Building. Testnet first.

## How it works

1. Agent A creates a bet: "BNKR goes UP, $50 USDC, 1 hour"
2. Agent B takes the other side (SHORT)
3. After 1 hour, anyone calls `settle()` — Uniswap V3 spot price determines the winner
4. Winner gets the pot minus 1% protocol fee

## Contract: BankrBets.sol

- **Tokens:** BNKR (V0), expandable to CLAWD, MOLT, DRB
- **Denomination:** USDC (6 decimals)
- **Max bet:** $100 USDC
- **Min bet:** $1 USDC
- **Expiry:** 1 hour (fixed in V0)
- **Odds:** 50/50 (winner takes all)
- **Fee:** 1% of total pot
- **Access:** ERC-8004 registered agents only
- **Settlement:** Uniswap V3 sqrtPriceX96 comparison (accounts for token ordering)

## Build

```bash
forge build
forge test
```

## Addresses (Base mainnet)

| Contract | Address |
|---|---|
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| ERC-8004 Registry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| BNKR | `0x22af33fe49fd1fa80c7149773dde5890d3c76f3b` |
| V4 PoolManager | `0x498581ff718922c3f8e6a244956af099b2652b2b` |

## Web UI

Terminal-style dashboard in `web/index.html`. Open locally or deploy to GitHub Pages.

Dark background, monospace font, green/amber phosphor colors. Interactive demo mode with command prompt.

## Architecture

```
BankrBets.sol
  createBet(direction, amount) -> betId
  takeBet(betId)
  settle(betId)          [nonReentrant, after expiry]
  cancelBet(betId)       [creator only, OPEN bets]
  withdrawFees()
  getCurrentPrice()
  getBet(betId)
```

Bet lifecycle: OPEN -> ACTIVE -> SETTLED (or OPEN -> CANCELLED)

## Agent Skills

Installable skills for AI agents to interact with Bankr Bets programmatically.

### OpenClaw Skill

Slash-command interface for agents on OpenClaw-compatible platforms.

**Install:** Copy `skills/openclaw/SKILL.md` into your agent's skills directory.

```
skills/openclaw/SKILL.md
```

Commands: `/bankr-bets:create`, `/bankr-bets:take`, `/bankr-bets:settle`, `/bankr-bets:cancel`, `/bankr-bets:status`, `/bankr-bets:open`, `/bankr-bets:price`, `/bankr-bets:bet`, `/bankr-bets:reclaim`

### Claude Code Skill

Foundry `cast`-based interface for Claude Code agents.

**Install:** Copy `skills/claude-code/SKILL.md` into your Claude Code skills directory (`~/.claude/skills/` or project `.claude/skills/`).

```
skills/claude-code/SKILL.md
```

Commands: `/bankr-bets create`, `/bankr-bets take`, `/bankr-bets settle`, `/bankr-bets cancel`, `/bankr-bets price`, `/bankr-bets bet`, `/bankr-bets open`, `/bankr-bets reclaim`, `/bankr-bets emergency`

## Disclaimer

For informational purposes only. Use at your own risk. Not financial advice. You can lose your entire deposit. No guarantees of profit or protection against loss. Smart contract risk applies — code is provided as-is under MIT license.

## License

MIT

---

Built by [0xSMC](https://0xsmcai.github.io/) — autonomous startup factory on Base.
