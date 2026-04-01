---
name: bankr-bets
description: Bet on Bankr ecosystem token prices (DRB, BNKR). Binary prediction market on Base. Use when the user wants to bet UP or DOWN on token prices, check open markets, view their bets, claim winnings, or check the leaderboard. Parimutuel model (pool-based, winners split losers' pot).
metadata:
  openclaw:
    emoji: "🎲"
    homepage: "https://github.com/0xsmcai/bankr-bets"
---

# Bankr Bets

Bet on where DRB and BNKR prices go next. UP or DOWN. Winners split the pot.

This is a parimutuel prediction market on Base. Everyone's bets go into a pool. When the market closes, the oracle reads the price. The winning side splits the losing side's money, minus a 3% fee.

## Quick start

```
/bankr-bets markets          — see what's open
/bankr-bets bet 1 UP 100     — bet $100 that market 1 goes UP
/bankr-bets status            — your active bets
/bankr-bets claim 1           — claim winnings from market 1
```

## Contract

- **Chain:** Base (chain ID 8453) / Base Sepolia (chain ID 84532) for testnet
- **Contract:** See `deployments/base-sepolia.json` in the repo for current addresses
- **Collateral:** USDC (6 decimals)
- **ABI:** `abi/BankrBets.json` in the repo

## Commands

### /bankr-bets markets

List all active markets. Shows: market ID, token, duration, time remaining, total UP/DOWN pool, implied odds.

**How to read it:**
```bash
# Get the number of markets
cast call $BANKR_BETS "nextMarketId()(uint256)" --rpc-url $RPC

# Get details for a specific market
cast call $BANKR_BETS "getMarket(uint256)((address,address,bool,uint8,uint48,uint48,uint48,int24,uint8,uint128,uint128,uint128,bool))" $MARKET_ID --rpc-url $RPC
```

**Via Bankr API:**
```bash
curl -X POST https://api.bankr.bot/wallet/submit \
  -H "X-API-Key: $BANKR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 84532,
    "to": "'$BANKR_BETS'",
    "data": "'$(cast calldata "getMarket(uint256)" $MARKET_ID)'"
  }'
```

### /bankr-bets bet <marketId> <UP|DOWN> <amount>

Place a bet on a market. Amount is in USDC (e.g., 100 = $100).

**Steps:**
1. Approve USDC spending
2. Call bet() on the contract

```bash
# 1. Approve USDC (amount in 6 decimals, so $100 = 100000000)
AMOUNT_RAW=$((AMOUNT * 1000000))
cast send $USDC "approve(address,uint256)" $BANKR_BETS $AMOUNT_RAW --rpc-url $RPC --private-key $KEY

# 2. Place the bet (isUp = true for UP, false for DOWN)
IS_UP=true  # or false for DOWN
cast send $BANKR_BETS "bet(uint256,bool,uint256)" $MARKET_ID $IS_UP $AMOUNT_RAW --rpc-url $RPC --private-key $KEY
```

**Via Bankr API:**
```bash
# Step 1: Approve
curl -X POST https://api.bankr.bot/wallet/submit \
  -H "X-API-Key: $BANKR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 84532,
    "to": "'$USDC'",
    "data": "'$(cast calldata "approve(address,uint256)" $BANKR_BETS $AMOUNT_RAW)'"
  }'

# Step 2: Bet
curl -X POST https://api.bankr.bot/wallet/submit \
  -H "X-API-Key: $BANKR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 84532,
    "to": "'$BANKR_BETS'",
    "data": "'$(cast calldata "bet(uint256,bool,uint256)" $MARKET_ID $IS_UP $AMOUNT_RAW)'"
  }'
```

**Limits:**
- Min bet: $1
- Max bet: $1,000
- Max per market: $10,000
- Max per user across all markets: $5,000

### /bankr-bets status

Check your position in a market.

```bash
cast call $BANKR_BETS "getPosition(uint256,address)((uint128,uint8,bool,bool))" $MARKET_ID $YOUR_ADDRESS --rpc-url $RPC
```

Returns: `(amount, side, claimed, isAgent)`
- side: 0 = no bet, 1 = UP, 2 = DOWN
- claimed: true if already claimed

### /bankr-bets claim <marketId>

Claim your winnings (or clear your exposure for a loss).

```bash
cast send $BANKR_BETS "claim(uint256)" $MARKET_ID --rpc-url $RPC --private-key $KEY
```

**Via Bankr API:**
```bash
curl -X POST https://api.bankr.bot/wallet/submit \
  -H "X-API-Key: $BANKR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 84532,
    "to": "'$BANKR_BETS'",
    "data": "'$(cast calldata "claim(uint256)" $MARKET_ID)'"
  }'
```

**Payout rules:**
- Winners get a proportional share of 97% of the pool (3% fee)
- Losers get 0 but must claim to clear their exposure for future bets
- Voided markets return the full deposit, no fees

### /bankr-bets price

Read the current TWAP tick for a token's pool. Useful for predicting which way the market will resolve.

```bash
# Get the pool address from the market
cast call $BANKR_BETS "getMarket(uint256)" $MARKET_ID --rpc-url $RPC

# Read the pool's current tick
cast call $POOL "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" --rpc-url $RPC
```

The second return value (int24) is the current tick. Compare it to the market's openingTick to see which direction price has moved.

## Events

Listen to these events for real-time market data:

```
MarketCreated(uint256 indexed marketId, address indexed token, uint8 duration, uint48 openTime, uint48 closeTime, int24 openingTick)
BetPlaced(uint256 indexed marketId, address indexed bettor, bool isUp, uint256 amount, bool isAgent)
MarketResolved(uint256 indexed marketId, uint8 outcome, int24 closingTick)
Claimed(uint256 indexed marketId, address indexed bettor, uint256 payout)
```

## Market timing

| Duration | Betting closes | Resolves after |
|----------|---------------|----------------|
| 1 hour | 15 min before close | Close time |
| 4 hours | 30 min before close | Close time |
| 24 hours | 60 min before close | Close time |

Markets that aren't resolved within 4 hours of close are automatically voided (full refund).

## Testnet setup

On testnet, you need mock USDC. The deployer can mint it:

```bash
cast send $MOCK_USDC "mint(address,uint256)" $YOUR_ADDRESS 10000000000 --rpc-url $RPC --private-key $DEPLOYER_KEY
```

This gives you 10,000 mock USDC to play with.

## Source code

- Contract: [`src/BankrBets.sol`](https://github.com/0xsmcai/bankr-bets/blob/main/src/BankrBets.sol)
- ABI: [`abi/BankrBets.json`](https://github.com/0xsmcai/bankr-bets/blob/main/abi/BankrBets.json)
- Addresses: [`deployments/`](https://github.com/0xsmcai/bankr-bets/tree/main/deployments)
- Architecture: [`ARCHITECTURE.md`](https://github.com/0xsmcai/bankr-bets/blob/main/ARCHITECTURE.md)
