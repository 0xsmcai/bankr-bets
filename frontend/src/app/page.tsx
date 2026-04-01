'use client'

import { useAccount, useConnect, useDisconnect, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { BANKR_BETS_ADDRESS, BANKR_BETS_ABI, USDC_ADDRESS, USDC_ABI, BLOCK_EXPLORER } from '@/config/contracts'
import { useState, useEffect, useMemo } from 'react'
import { formatUnits, parseUnits, type Address } from 'viem'

// ── Constants ──────────────────────────────────────────────────

const DURATION_LABELS: Record<number, string> = { 0: '1H', 1: '4H', 2: '24H' }
const OUTCOME_LABELS: Record<number, string> = { 0: 'OPEN', 1: 'UP', 2: 'DOWN', 3: 'VOIDED' }

const TOKEN_NAMES: Record<string, string> = {
  '0x0000000000000000000000000000000000000d4b': 'DRB',
  '0x000000000000000000000000000000000000b14c': 'BNKR',
  '0x000000000000000000000000000000000000b14C': 'BNKR',
}

function tokenName(addr: string): string {
  return TOKEN_NAMES[addr.toLowerCase()] || TOKEN_NAMES[addr] || addr.slice(0, 8)
}

function formatUSDC(amount: bigint): string {
  return `$${Number(formatUnits(amount, 6)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function timeLeft(ts: number): string {
  const now = Math.floor(Date.now() / 1000)
  const diff = ts - now
  if (diff <= 0) return 'CLOSED'
  const h = Math.floor(diff / 3600)
  const m = Math.floor((diff % 3600) / 60)
  const s = diff % 60
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${s}s`
  return `${s}s`
}

type Tab = 'active' | 'resolved' | 'portfolio'

// ── Header ─────────────────────────────────────────────────────

function Header() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  const { data: balance } = useReadContract({
    address: USDC_ADDRESS,
    abi: USDC_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  })

  return (
    <header className="flex items-center justify-between px-5 md:px-6 py-4 border-b border-[rgba(212,208,200,0.1)]">
      <div>
        <h1 className="text-xl" style={{ fontFamily: 'var(--font-display)' }}>
          <span className="text-crimson">Bankr</span> Bets
        </h1>
        <p className="text-xs text-muted mono">PARIMUTUEL PREDICTION MARKET ON BASE</p>
      </div>
      <div>
        {isConnected ? (
          <div className="flex items-center gap-3">
            {balance !== undefined && (
              <span className="mono text-xs text-amber">{formatUSDC(balance as bigint)}</span>
            )}
            <span className="mono text-xs text-chrome hidden sm:inline">
              {address?.slice(0, 6)}...{address?.slice(-4)}
            </span>
            <button className="btn text-xs" onClick={() => disconnect()}>×</button>
          </div>
        ) : (
          <button className="btn btn-primary" onClick={() => connect({ connector: connectors[0] })}>
            CONNECT
          </button>
        )}
      </div>
    </header>
  )
}

// ── Onboarding ─────────────────────────────────────────────────

function Onboarding() {
  const { isConnected } = useAccount()
  const [dismissed, setDismissed] = useState(false)

  useEffect(() => {
    if (typeof window !== 'undefined' && localStorage.getItem('bankrbets-onboarded')) {
      setDismissed(true)
    }
  }, [])

  if (dismissed || isConnected) return null

  return (
    <div className="border border-[rgba(212,208,200,0.1)] p-5 mb-6">
      <h3 className="text-amber mono text-sm mb-3">HOW IT WORKS</h3>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm">
        <div>
          <span className="mono text-xs text-teal">01</span>
          <p className="mt-1">Connect your wallet and mint free testnet USDC from the faucet.</p>
        </div>
        <div>
          <span className="mono text-xs text-teal">02</span>
          <p className="mt-1">Pick a market and bet UP or DOWN on the token price.</p>
        </div>
        <div>
          <span className="mono text-xs text-teal">03</span>
          <p className="mt-1">If you're right, claim your share of the losing side's pot.</p>
        </div>
      </div>
      <button
        className="mono text-xs text-muted mt-4 hover:text-amber transition-colors"
        onClick={() => { setDismissed(true); localStorage.setItem('bankrbets-onboarded', '1') }}
      >
        DISMISS
      </button>
    </div>
  )
}

// ── Testnet Faucet ─────────────────────────────────────────────

function TestnetFaucet() {
  const { address } = useAccount()
  const { writeContract: mint, data: mintTx } = useWriteContract()
  const { isLoading: minting, isSuccess: minted } = useWaitForTransactionReceipt({ hash: mintTx })

  if (!address) return null

  return (
    <div className="border border-dashed border-[rgba(212,208,200,0.1)] p-4 mb-6">
      <div className="flex items-center justify-between">
        <div>
          <p className="mono text-xs text-amber">TESTNET FAUCET</p>
          <p className="text-xs text-muted mt-1">Free mock USDC for Base Sepolia</p>
        </div>
        <button className="btn text-xs" onClick={() => mint({
          address: USDC_ADDRESS,
          abi: USDC_ABI,
          functionName: 'mint',
          args: [address, parseUnits('10000', 6)],
        })} disabled={minting}>
          {minting ? 'MINTING...' : minted ? 'MINTED' : 'GET 10K USDC'}
        </button>
      </div>
    </div>
  )
}

// ── Market Card ────────────────────────────────────────────────

function MarketCard({ marketId }: { marketId: bigint }) {
  const { address } = useAccount()
  const [betAmount, setBetAmount] = useState('')
  const [betSide, setBetSide] = useState<boolean | null>(null)
  const [now, setNow] = useState(Math.floor(Date.now() / 1000))

  useEffect(() => {
    const timer = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(timer)
  }, [])

  const { data: market } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getMarket',
    args: [marketId],
    query: { refetchInterval: 4000 },
  })

  const { data: position } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getPosition',
    args: address ? [marketId, address] : undefined,
    query: { enabled: !!address, refetchInterval: 4000 },
  })

  const { writeContract: approve, data: approveTx, reset: resetApprove } = useWriteContract()
  const { writeContract: placeBet, data: betTx } = useWriteContract()
  const { writeContract: claimWinnings, data: claimTx } = useWriteContract()

  const { isSuccess: approved } = useWaitForTransactionReceipt({ hash: approveTx })
  const { isLoading: betting } = useWaitForTransactionReceipt({ hash: betTx })
  const { isLoading: claiming } = useWaitForTransactionReceipt({ hash: claimTx })

  useEffect(() => {
    if (approved && betSide !== null && betAmount) {
      try {
        const amount = parseUnits(betAmount, 6)
        placeBet({
          address: BANKR_BETS_ADDRESS,
          abi: BANKR_BETS_ABI,
          functionName: 'bet',
          args: [marketId, betSide, amount],
        })
      } catch { /* invalid amount, ignore */ }
      setBetSide(null)
      setBetAmount('')
      resetApprove()
    }
  }, [approved])

  if (!market) return null

  const isOpen = market.outcome === 0 && !market.resolved
  const isResolved = market.resolved
  const closeTime = Number(market.closeTime)
  const bettingDeadline = Number(market.bettingDeadline)
  const canBet = isOpen && now < bettingDeadline
  const bettingEnded = isOpen && now >= bettingDeadline

  const upPct = market.totalPool > 0n ? Number(market.totalUp * 100n / market.totalPool) : 50
  const downPct = market.totalPool > 0n ? 100 - upPct : 50

  const hasPosition = position && (position as any).amount > 0n
  const pos = position as any
  const userSide = pos?.side === 1 ? 'UP' : pos?.side === 2 ? 'DOWN' : null
  const canClaim = isResolved && hasPosition && !pos?.claimed

  // Implied payout multiplier
  const upMulti = market.totalPool > 0n && market.totalUp > 0n
    ? (Number(market.totalPool) / Number(market.totalUp)).toFixed(2)
    : '—'
  const downMulti = market.totalPool > 0n && market.totalDown > 0n
    ? (Number(market.totalPool) / Number(market.totalDown)).toFixed(2)
    : '—'

  function handleBet(isUp: boolean) {
    if (!betAmount || !address) return
    let amount: bigint
    try {
      amount = parseUnits(betAmount, 6)
    } catch { return }
    setBetSide(isUp)
    approve({
      address: USDC_ADDRESS,
      abi: USDC_ABI,
      functionName: 'approve',
      args: [BANKR_BETS_ADDRESS, amount],
    })
  }

  return (
    <div className="border border-[rgba(212,208,200,0.1)] p-5 mb-3 hover:border-[rgba(212,208,200,0.2)] transition-colors">
      {/* Header row */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="mono text-xs text-muted">#{marketId.toString()}</span>
          <span className="mono text-sm font-bold" style={{ color: 'var(--text-bright)' }}>
            {tokenName(market.token)}
          </span>
          <span className="mono text-xs text-teal">{DURATION_LABELS[market.duration] || '?'}</span>
        </div>
        <div className="mono text-xs">
          {isResolved ? (
            <span className={market.outcome === 1 ? 'text-green-400' : market.outcome === 2 ? 'text-red-400' : 'text-amber'}>
              {OUTCOME_LABELS[market.outcome]}
            </span>
          ) : bettingEnded ? (
            <span className="text-muted">BETTING CLOSED · resolves {timeLeft(closeTime)}</span>
          ) : (
            <span className="text-chrome">bet closes {timeLeft(bettingDeadline)}</span>
          )}
        </div>
      </div>

      {/* Odds bar */}
      <div className="mb-3">
        <div className="flex justify-between mono text-xs mb-1">
          <span className="text-green-400">UP {upPct}% <span className="text-muted">({upMulti}x)</span></span>
          <span className="text-red-400"><span className="text-muted">({downMulti}x)</span> {downPct}% DOWN</span>
        </div>
        <div className="flex h-1.5 bg-[rgba(212,208,200,0.05)] overflow-hidden">
          <div className="bg-green-400/30 transition-all duration-500" style={{ width: `${upPct}%` }} />
          <div className="bg-red-400/30 transition-all duration-500" style={{ width: `${downPct}%` }} />
        </div>
        <div className="flex justify-between mono text-xs mt-1 text-muted">
          <span>{formatUSDC(market.totalUp)}</span>
          <span>Pool: {formatUSDC(market.totalPool)}</span>
          <span>{formatUSDC(market.totalDown)}</span>
        </div>
      </div>

      {/* User position */}
      {hasPosition && (
        <div className="mono text-xs p-2 mb-3 border border-[rgba(212,208,200,0.05)] bg-[rgba(212,208,200,0.02)]">
          Your bet: {formatUSDC(pos.amount)} {userSide}
          {pos.isAgent && <span className="text-teal ml-2">[AGENT]</span>}
          {pos.claimed && <span className="text-muted ml-2">[CLAIMED]</span>}
        </div>
      )}

      {/* Bet controls */}
      {canBet && address && (
        <div className="flex gap-2 items-center">
          <input
            type="number"
            placeholder="USDC"
            value={betAmount}
            onChange={(e) => setBetAmount(e.target.value)}
            className="mono text-sm bg-transparent border border-[rgba(212,208,200,0.1)] px-3 py-2 w-28 text-right outline-none focus:border-[var(--amber)]"
            style={{ color: 'var(--text-bright)' }}
            min="1"
            max="1000"
          />
          <button className="btn btn-up text-xs" onClick={() => handleBet(true)} disabled={!!approveTx || betting}>
            {approveTx || betting ? '...' : 'UP ↑'}
          </button>
          <button className="btn btn-down text-xs" onClick={() => handleBet(false)} disabled={!!approveTx || betting}>
            {approveTx || betting ? '...' : 'DOWN ↓'}
          </button>
        </div>
      )}

      {/* Claim button */}
      {canClaim && (
        <button className="btn btn-primary w-full mt-2 text-xs" onClick={() => claimWinnings({
          address: BANKR_BETS_ADDRESS,
          abi: BANKR_BETS_ABI,
          functionName: 'claim',
          args: [marketId],
        })} disabled={claiming}>
          {claiming ? 'CLAIMING...' : 'CLAIM WINNINGS'}
        </button>
      )}
    </div>
  )
}

// ── Tab Navigation ─────────────────────────────────────────────

function TabNav({ active, onChange }: { active: Tab; onChange: (t: Tab) => void }) {
  const tabs: { id: Tab; label: string }[] = [
    { id: 'active', label: 'ACTIVE' },
    { id: 'resolved', label: 'RESOLVED' },
    { id: 'portfolio', label: 'MY BETS' },
  ]

  return (
    <div className="flex gap-1 mb-4">
      {tabs.map(t => (
        <button
          key={t.id}
          className={`mono text-xs px-4 py-2 border transition-colors ${
            active === t.id
              ? 'border-[var(--amber)] text-amber'
              : 'border-[rgba(212,208,200,0.1)] text-muted hover:text-chrome'
          }`}
          onClick={() => onChange(t.id)}
        >
          {t.label}
        </button>
      ))}
    </div>
  )
}

// ── Main Page ──────────────────────────────────────────────────

export default function Home() {
  const { address } = useAccount()
  const [tab, setTab] = useState<Tab>('active')

  const { data: nextId } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'nextMarketId',
    query: { refetchInterval: 5000 },
  })

  const marketCount = nextId ? Number(nextId) - 1 : 0
  const allMarketIds = useMemo(
    () => Array.from({ length: marketCount }, (_, i) => BigInt(i + 1)).reverse(),
    [marketCount]
  )

  return (
    <div className="max-w-[720px] mx-auto px-5 pb-16">
      <Header />

      <div className="mt-8 mb-4">
        <h2>Markets</h2>
        <p className="text-sm text-muted mt-1">
          Bet UP or DOWN on Bankr ecosystem token prices. Winners split the pot. Parimutuel — no counterparty, no house edge.
        </p>
      </div>

      <Onboarding />
      <TestnetFaucet />

      <TabNav active={tab} onChange={setTab} />

      {tab === 'portfolio' && !address ? (
        <div className="text-center py-12 text-muted">
          <p className="mono text-sm">CONNECT WALLET</p>
          <p className="text-xs mt-2">Connect your wallet to see your bets.</p>
        </div>
      ) : marketCount === 0 ? (
        <div className="text-center py-12 text-muted">
          <p className="mono text-sm">NO MARKETS YET</p>
          <p className="text-xs mt-2">The keeper bot creates markets every hour. Check back soon.</p>
        </div>
      ) : (
        <MarketList marketIds={allMarketIds} tab={tab} userAddress={address} />
      )}

      <footer className="mt-16 pt-6 border-t border-[rgba(212,208,200,0.05)] text-center">
        <p className="mono text-xs" style={{ color: 'var(--text-dim)' }}>
          Built by{' '}
          <a href="https://0xsmcai.github.io/" target="_blank" rel="noopener">SMCFactory</a>
          {' · '}
          <a href="https://github.com/0xsmcai/bankr-bets" target="_blank" rel="noopener">GitHub</a>
          {' · '}
          <a href={`${BLOCK_EXPLORER}/address/${BANKR_BETS_ADDRESS}`} target="_blank" rel="noopener">Contract</a>
        </p>
        <p className="mono text-xs mt-2" style={{ color: 'var(--text-dim)' }}>
          TESTNET ONLY · NOT AUDITED FOR MAINNET · NOT FINANCIAL ADVICE
        </p>
      </footer>
    </div>
  )
}

// ── Market List with Filtering ─────────────────────────────────

function MarketList({ marketIds, tab, userAddress }: { marketIds: bigint[]; tab: Tab; userAddress?: Address }) {
  // Read all markets to enable filtering
  // For simplicity, render all cards and let each card self-filter via CSS
  // This works well for <100 markets
  return (
    <div>
      {marketIds.map(id => (
        <FilteredMarketCard key={id.toString()} marketId={id} tab={tab} userAddress={userAddress} />
      ))}
    </div>
  )
}

function FilteredMarketCard({ marketId, tab, userAddress }: { marketId: bigint; tab: Tab; userAddress?: Address }) {
  const { data: market } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getMarket',
    args: [marketId],
    query: { refetchInterval: 5000 },
  })

  const { data: position } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getPosition',
    args: userAddress ? [marketId, userAddress] : undefined,
    query: { enabled: !!userAddress && tab === 'portfolio', refetchInterval: 5000 },
  })

  if (!market) return null

  const isResolved = market.resolved
  const isActive = !isResolved

  if (tab === 'active' && !isActive) return null
  if (tab === 'resolved' && !isResolved) return null
  if (tab === 'portfolio') {
    if (!position || (position as any).amount === 0n) return null
  }

  return <MarketCard marketId={marketId} />
}
