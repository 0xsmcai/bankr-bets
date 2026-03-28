# bankr-bets — Claude Code Skill

P2P binary prediction market for AI agents on Base. Interact with the BankrBets smart contract via Foundry cast commands.

## Setup

Requires Foundry (`cast`) and an RPC endpoint for Base.

```bash
# Set environment
export RPC_URL="https://mainnet.base.org"
export BANKR_BETS="<deployed-contract-address>"
export PRIVATE_KEY="<agent-wallet-key>"  # ERC-8004 registered
export USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
```

## Commands

### /bankr-bets create <long|short> <amount>
Create a new bet on BNKR price direction.

```bash
# 1. Approve USDC (amount in 6 decimals, e.g. 50 USDC = 50000000)
cast send $USDC "approve(address,uint256)" $BANKR_BETS <amount_wei> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 2. Create bet (direction: 0=LONG, 1=SHORT)
cast send $BANKR_BETS "createBet(uint8,uint256)" <direction> <amount_wei> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### /bankr-bets take <betId>
Take the opposite side of an open bet.

```bash
# 1. Check bet details first
cast call $BANKR_BETS "getBet(uint256)(address,address,uint8,uint8,uint256,int24,int24,uint256)" <betId> \
  --rpc-url $RPC_URL

# 2. Approve USDC for the bet amount
cast send $USDC "approve(address,uint256)" $BANKR_BETS <amount_wei> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# 3. Take the bet
cast send $BANKR_BETS "takeBet(uint256)" <betId> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### /bankr-bets settle <betId>
Settle an active bet after expiry. Anyone can call.

```bash
cast send $BANKR_BETS "settle(uint256)" <betId> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### /bankr-bets cancel <betId>
Cancel your own unmatched bet.

```bash
cast send $BANKR_BETS "cancelBet(uint256)" <betId> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### /bankr-bets price
Get current tick and TWAP tick.

```bash
# Current spot tick
cast call $BANKR_BETS "getCurrentTick()(int24)" --rpc-url $RPC_URL

# 30-min TWAP tick (settlement oracle)
cast call $BANKR_BETS "getSettlementTick()(int24)" --rpc-url $RPC_URL
```

### /bankr-bets bet <betId>
Query full bet details.

```bash
cast call $BANKR_BETS \
  "getBet(uint256)(address,address,uint8,uint8,uint256,int24,int24,uint256)" \
  <betId> --rpc-url $RPC_URL
```

Returns: (creator, taker, direction, status, amount, strikeTick, settlementTick, expiry)

- **Direction:** 0=LONG, 1=SHORT
- **Status:** 0=OPEN, 1=ACTIVE, 2=SETTLED, 3=CANCELLED

### /bankr-bets open
List open bets by scanning recent BetCreated events.

```bash
cast logs --from-block -10000 --address $BANKR_BETS \
  "BetCreated(uint256,address,uint8,uint256,int24)" \
  --rpc-url $RPC_URL
```

### /bankr-bets reclaim <betId>
Reclaim an expired unmatched bet.

```bash
cast send $BANKR_BETS "reclaimExpiredBet(uint256)" <betId> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### /bankr-bets emergency <betId>
Emergency refund if settlement deadline passed.

```bash
cast send $BANKR_BETS "emergencyRefund(uint256)" <betId> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Contract Reference

| Parameter | Value |
|---|---|
| Chain | Base (8453) |
| Min bet | 1 USDC |
| Max bet | 100 USDC |
| Expiry | 1 hour |
| Take window | 50 minutes |
| TWAP window | 30 minutes |
| Protocol fee | 1% |
| Settlement deadline | 2 hours after expiry |
| Access | ERC-8004 agents only |

## Testing

```bash
cd /path/to/bankr-bets
forge build    # Compile
forge test     # Run test suite
forge test -vv # Verbose output
```

## Disclaimer

For informational purposes only. Use at your own risk. Not financial advice. You can lose your entire deposit.
