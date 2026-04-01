/**
 * Bankr Bets Keeper Bot
 *
 * Creates markets on schedule, resolves them after close.
 * Uses the deploy wallet (set as keeper in the contract).
 * Reads config from deployments/base-sepolia.json.
 *
 * Run: KEEPER_KEY=0x... npx tsx keeper/index.ts
 */

import { createPublicClient, createWalletClient, http, parseAbi, type Hex } from 'viem'
import { baseSepolia } from 'viem/chains'
import { privateKeyToAccount } from 'viem/accounts'
import { readFileSync } from 'fs'
import { resolve } from 'path'

// ── Config ──────────────────────────────────────────────────────

const PRIVATE_KEY = process.env.KEEPER_KEY as Hex
if (!PRIVATE_KEY) {
  console.error('KEEPER_KEY env var required')
  process.exit(1)
}

const deployment = JSON.parse(
  readFileSync(resolve(__dirname, '../deployments/base-sepolia.json'), 'utf-8')
)

const BANKR_BETS = deployment.contracts.BankrBets as Hex
const RPC = deployment.rpc

// Duration enum values matching the contract
const Duration = { ONE_HOUR: 0, FOUR_HOUR: 1, DAILY: 2 } as const

// Token addresses (mock addresses from testnet deploy)
const DRB = '0x0000000000000000000000000000000000000d4b' as Hex
const BNKR = '0x000000000000000000000000000000000000b14C' as Hex

// ── ABI (minimal — only what the keeper calls) ──────────────────

const abi = parseAbi([
  'function createMarket(address token, uint8 duration) external returns (uint256)',
  'function resolve(uint256 marketId, int24 offChainTick) external',
  'function resolveByTwap(uint256 marketId) external',
  'function getMarket(uint256 marketId) external view returns ((address token, address pool, bool isToken0, uint8 duration, uint48 openTime, uint48 closeTime, uint48 bettingDeadline, int24 openingTick, uint8 outcome, uint128 totalUp, uint128 totalDown, uint128 totalPool, bool resolved))',
  'function nextMarketId() external view returns (uint256)',
  'event MarketCreated(uint256 indexed marketId, address indexed token, uint8 duration, uint48 openTime, uint48 closeTime, int24 openingTick)',
  'event MarketResolved(uint256 indexed marketId, uint8 outcome, int24 closingTick)',
])

const poolAbi = parseAbi([
  'function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)',
])

// ── Clients ─────────────────────────────────────────────────────

const account = privateKeyToAccount(PRIVATE_KEY)

const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(RPC),
})

const walletClient = createWalletClient({
  account,
  chain: baseSepolia,
  transport: http(RPC),
})

// ── Helpers ─────────────────────────────────────────────────────

function log(msg: string) {
  console.log(`[${new Date().toISOString()}] ${msg}`)
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))

async function getCurrentTick(poolAddress: Hex): Promise<number> {
  const result = await publicClient.readContract({
    address: poolAddress,
    abi: poolAbi,
    functionName: 'slot0',
  })
  return Number(result[1])
}

// Track the last hour we created markets in, to prevent duplicate creation on restarts
let lastCreatedHour = -1

// Track the lowest unresolved market ID to avoid scanning resolved history
let lowestUnresolved = 1n

// ── Create Markets ──────────────────────────────────────────────

async function createMarkets() {
  const hour = new Date().getUTCHours()
  const minute = new Date().getUTCMinutes()

  // Only create near top of hour (first 3 minutes), and only once per hour
  if (minute > 2) return
  if (hour === lastCreatedHour) return
  lastCreatedHour = hour

  const tokens = [
    { address: DRB, name: 'DRB', pool: deployment.contracts.DRBPool as Hex },
    { address: BNKR, name: 'BNKR', pool: deployment.contracts.BNKRPool as Hex },
  ]

  for (let i = 0; i < tokens.length; i++) {
    if (i > 0) await sleep(2000) // let nonce settle between tokens
    const token = tokens[i]

    // Always create 1-hour markets
    try {
      const hash = await walletClient.writeContract({
        address: BANKR_BETS,
        abi,
        functionName: 'createMarket',
        args: [token.address, Duration.ONE_HOUR],
      })
      await publicClient.waitForTransactionReceipt({ hash })
      log(`Created 1h ${token.name} market. TX: ${hash}`)
    } catch (e: any) {
      log(`Failed to create 1h ${token.name}: ${e.message?.slice(0, 100)}`)
    }

    // 4-hour markets at 00, 04, 08, 12, 16, 20 UTC
    if (hour % 4 === 0) {
      try {
        const hash = await walletClient.writeContract({
          address: BANKR_BETS,
          abi,
          functionName: 'createMarket',
          args: [token.address, Duration.FOUR_HOUR],
        })
        await publicClient.waitForTransactionReceipt({ hash })
        log(`Created 4h ${token.name} market. TX: ${hash}`)
      } catch (e: any) {
        log(`Failed to create 4h ${token.name}: ${e.message?.slice(0, 100)}`)
      }
    }

    // Daily markets at 00 UTC only
    if (hour === 0) {
      try {
        const hash = await walletClient.writeContract({
          address: BANKR_BETS,
          abi,
          functionName: 'createMarket',
          args: [token.address, Duration.DAILY],
        })
        await publicClient.waitForTransactionReceipt({ hash })
        log(`Created 24h ${token.name} market. TX: ${hash}`)
      } catch (e: any) {
        log(`Failed to create 24h ${token.name}: ${e.message?.slice(0, 100)}`)
      }
    }
  }
}

// ── Resolve Markets ─────────────────────────────────────────────

async function resolveMarkets() {
  const nextId = await publicClient.readContract({
    address: BANKR_BETS,
    abi,
    functionName: 'nextMarketId',
  })

  const now = Math.floor(Date.now() / 1000)

  // Only scan from lowest known unresolved market
  for (let id = lowestUnresolved; id < nextId; id++) {
    try {
      const market = await publicClient.readContract({
        address: BANKR_BETS,
        abi,
        functionName: 'getMarket',
        args: [id],
      })

      if (market.resolved) {
        // Advance the low-water mark past contiguous resolved markets
        if (id === lowestUnresolved) lowestUnresolved = id + 1n
        continue
      }

      // Skip markets that haven't closed yet
      const closeTime = Number(market.closeTime)
      if (now < closeTime) continue

      const offChainTick = await getCurrentTick(market.pool as Hex)

      log(`Resolving market ${id} (token: ${market.token}, offChainTick: ${offChainTick})`)

      const hash = await walletClient.writeContract({
        address: BANKR_BETS,
        abi,
        functionName: 'resolve',
        args: [id, offChainTick],
      })
      await publicClient.waitForTransactionReceipt({ hash })

      log(`Resolved market ${id}. TX: ${hash}`)

      if (id === lowestUnresolved) lowestUnresolved = id + 1n
    } catch (e: any) {
      if (!e.message?.includes('MarketAlreadyResolved') && !e.message?.includes('MarketNotClosed')) {
        log(`Error resolving market ${id}: ${e.message?.slice(0, 150)}`)
      }
    }
  }
}

// ── Main Loop (serialized via recursive setTimeout) ─────────────

async function tick() {
  try {
    await createMarkets()
    await resolveMarkets()
  } catch (e: any) {
    log(`Tick error: ${e.message?.slice(0, 200)}`)
  }
  // Schedule next tick after this one completes (prevents overlap)
  setTimeout(tick, 60_000)
}

async function main() {
  log('Bankr Bets Keeper starting...')
  log(`Keeper address: ${account.address}`)
  log(`Contract: ${BANKR_BETS}`)
  log(`Chain: ${deployment.chain} (${deployment.chainId})`)

  // Initialize lowestUnresolved by scanning existing markets
  try {
    const nextId = await publicClient.readContract({
      address: BANKR_BETS,
      abi,
      functionName: 'nextMarketId',
    })
    for (let id = 1n; id < nextId; id++) {
      const market = await publicClient.readContract({
        address: BANKR_BETS,
        abi,
        functionName: 'getMarket',
        args: [id],
      })
      if (!market.resolved) {
        lowestUnresolved = id
        break
      }
      lowestUnresolved = id + 1n
    }
    log(`Lowest unresolved market: ${lowestUnresolved}`)
  } catch (e: any) {
    log(`Failed to initialize unresolved marker: ${e.message?.slice(0, 100)}`)
  }

  // Run first tick immediately, then recursive setTimeout handles the rest
  await tick()

  log('Keeper running. Checking every 60s.')
}

main().catch((e) => {
  console.error('Fatal:', e)
  process.exit(1)
})
