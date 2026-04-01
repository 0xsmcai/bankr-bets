# Bankr Bets

Parimutuel binary prediction market on Base. Players bet UP or DOWN on DRB and BNKR token prices. USDC collateral. Hybrid oracle (TWAP + off-chain keeper check).

## Project structure

```
src/BankrBets.sol          — the contract (~610 LOC)
test/BankrBets.t.sol       — 44 unit tests
script/DeployTestnet.s.sol — testnet deploy with mocks
abi/BankrBets.json         — exported ABI
deployments/               — chain-specific addresses
keeper/index.ts            — market creation + resolution bot
frontend/                  — Next.js dashboard (wagmi + viem)
skills/bankr-bets/         — agent skill (SKILL.md)
```

## Testing

```bash
forge build        # compile
forge test         # run all 44 tests
forge test -vvvv   # verbose with traces
```

Tests use mock contracts (MockUSDC, MockRegistry, MockV3Pool). Fork tests against real Base mainnet pools are planned but not yet implemented.

## Deployment

Testnet (Base Sepolia): addresses in `deployments/base-sepolia.json`.
Mainnet: not deployed. Requires professional audit first.

Deploy wallet is separate from the agent wallet (wallet separation rule).

## Key design decisions

- Single contract (no factory, no proxy) — simpler to audit
- USDC collateral (not ETH) — dollar-denominated caps
- Hybrid oracle (TWAP + keeper check) — catches manipulation
- Betting closes before TWAP window begins — prevents betting on known outcomes
- Emergency withdraw voids entire market — prevents insolvency
- Emergency withdraw only after MAX_RESOLUTION_DELAY — prevents race with resolution
- Market snapshots pool config at creation — prevents admin config change attack
- Agent tagging via ERC-8004 (try/catch, non-blocking) — powers leaderboard

## Keeper bot

The keeper creates markets on schedule and resolves them after close. It runs in a tmux session on the VPS.

```bash
KEEPER_KEY=0x... npx tsx keeper/index.ts
```

The keeper uses the deploy wallet, which is set as the keeper address in the contract.

## Frontend

Next.js + wagmi v2 + viem. Coinbase Smart Wallet (Base App) as primary connector. Hosted on GitHub Pages.

Design follows DESIGN.md (0xSMC visual system: dark warm brown, Space Grotesk/Satoshi/Space Mono, CRT scanlines).

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
