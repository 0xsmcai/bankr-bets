# Changelog

## 0.2.0 — 2026-04-01 (Frontend + Keeper Hardening)

### Frontend
- Full prediction market UI: market list, bet flow, claim, faucet
- Tab navigation: Active / Resolved / My Bets
- Onboarding flow for new users
- Token name display (DRB, BNKR) with countdown timers
- Payout multiplier display, USDC balance in header
- Mobile responsive design
- Deployed to GitHub Pages via Actions workflow
- Wallet: injected (MetaMask) + Coinbase Smart Wallet connectors
- Design system: DESIGN.md fully implemented (dark warm brown, Space Grotesk/Satoshi/Space Mono, CRT scanlines)

### Keeper Hardening
- Fixed BNKR market creation (address checksum + nonce race)
- Removed restart bootstrap (prevents duplicate market spam)
- Serialized tick loop (recursive setTimeout, no overlapping ticks)
- Efficient resolution: tracks lowestUnresolved, skips resolved history
- Transaction receipt waiting between all on-chain calls

### QA + Reviews
- QA: 3 issues found, 2 fixed (wallet fallback, empty state)
- Design review: all tokens match DESIGN.md
- Codex review: 6 findings, 4 fixed (keeper dedup, serialized loop, resolution scan, input validation)

### Security
- Frontend: no XSS sinks (React escaped values, no dangerouslySetInnerHTML)
- Input validation: parseUnits wrapped in try/catch
- Wallet separation maintained (deploy wallet for keeper only)

## 0.1.0 — 2026-04-01 (Testnet)

### Contract
- Parimutuel binary prediction market (BankrBets.sol, ~610 LOC)
- Markets: 1h, 4h, 24h durations for DRB and BNKR tokens
- USDC collateral with caps: $1K/bet, $10K/market, $5K/user, $30K/day
- Hybrid oracle: Uniswap V3 TWAP + keeper off-chain tick check
- 3% fee (2% treasury + 1% insurance) with double-call guard
- Emergency withdrawal voids entire market (prevents insolvency)
- Admin voidMarket() for mid-market emergencies
- Agent tagging via ERC-8004 registry (on-chain check)
- OpenZeppelin v5.1+: ReentrancyGuardTransient, SafeERC20, Math.mulDiv, Ownable2Step, Pausable

### Security
- 3 review cycles with 4 tools (review, cso, ethskills, codex)
- 22 findings found, all fixed:
  - bet() taking amount from allowance (was exploitable)
  - distributeFees() callable multiple times (was drainable)
  - userExposure never cleared for losers (permanent lockout)
  - emergencyWithdraw didn't update pool totals (insolvency)
  - emergencyWithdraw raceable via pause (loser could force void)
  - Late resolution TWAP exploit (added MAX_RESOLUTION_DELAY)
  - Token config mutable mid-market (added snapshot at creation)
  - Plus 15 additional LOW/INFO fixes
- 44 unit tests, all passing

### Infrastructure
- Deployed to Base Sepolia (testnet)
- Contract verified on Blockscout
- ABI exported (abi/BankrBets.json)
- Deployment addresses (deployments/base-sepolia.json)
- Keeper bot (keeper/index.ts) — creates and resolves markets on schedule
- Global git secret detection hook

### Tooling
- Foundry (Solidity 0.8.26, Cancun EVM, optimizer 800 runs)
- ethskills, base-skills, Blockscout MCP installed
- 8 audited reference repos cloned for security patterns
- gstack v0.15.1.0 for review pipeline
