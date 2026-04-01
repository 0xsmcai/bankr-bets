'use client'

import { useAccount, useConnect, useDisconnect, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { BANKR_BETS_ADDRESS, BANKR_BETS_ABI, USDC_ADDRESS, USDC_ABI, BLOCK_EXPLORER } from '@/config/contracts'
import { useState, useEffect } from 'react'
import { formatUnits, parseUnits } from 'viem'

const DURATION_LABELS: Record<number, string> = { 0: '1H', 1: '4H', 2: '24H' }
const OUTCOME_LABELS: Record<number, string> = { 0: 'OPEN', 1: 'UP', 2: 'DOWN', 3: 'VOIDED' }

function formatUSDC(amount: bigint): string {
  return `$${Number(formatUnits(amount, 6)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function timeLeft(closeTime: number): string {
  const now = Math.floor(Date.now() / 1000)
  const diff = closeTime - now
  if (diff <= 0) return 'CLOSED'
  const h = Math.floor(diff / 3600)
  const m = Math.floor((diff % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

function Header() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  return (
    <header className="flex items-center justify-between px-6 py-4 border-b border-[rgba(212,208,200,0.1)]">
      <div>
        <h1 className="text-xl" style={{ fontFamily: 'var(--font-display)' }}>
          <span className="text-crimson">Bankr</span> Bets
        </h1>
        <p className="text-xs text-muted mono">PARIMUTUEL PREDICTION MARKET</p>
      </div>
      <div>
        {isConnected ? (
          <div className="flex items-center gap-4">
            <span className="mono text-xs text-chrome">
              {address?.slice(0, 6)}...{address?.slice(-4)}
            </span>
            <button className="btn" onClick={() => disconnect()}>DISCONNECT</button>
          </div>
        ) : (
          <button className="btn btn-primary" onClick={() => connect({ connector: connectors[0] })}>
            CONNECT WALLET
          </button>
        )}
      </div>
    </header>
  )
}

function MarketCard({ marketId }: { marketId: bigint }) {
  const { address } = useAccount()
  const [betAmount, setBetAmount] = useState('')
  const [betSide, setBetSide] = useState<boolean | null>(null)

  const { data: market } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getMarket',
    args: [marketId],
    query: { refetchInterval: 2000 },
  })

  const { data: position } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'getPosition',
    args: address ? [marketId, address] : undefined,
    query: { enabled: !!address, refetchInterval: 2000 },
  })

  const { writeContract: approve, data: approveTx, reset: resetApprove } = useWriteContract()
  const { writeContract: placeBet, data: betTx } = useWriteContract()
  const { writeContract: claimWinnings, data: claimTx } = useWriteContract()

  const { isSuccess: approved } = useWaitForTransactionReceipt({ hash: approveTx })
  const { isLoading: betting } = useWaitForTransactionReceipt({ hash: betTx })
  const { isLoading: claiming } = useWaitForTransactionReceipt({ hash: claimTx })

  // After approval succeeds, place the bet
  useEffect(() => {
    if (approved && betSide !== null && betAmount) {
      const amount = parseUnits(betAmount, 6)
      placeBet({
        address: BANKR_BETS_ADDRESS,
        abi: BANKR_BETS_ABI,
        functionName: 'bet',
        args: [marketId, betSide, amount],
      })
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
  const canBet = isOpen && Math.floor(Date.now() / 1000) < bettingDeadline

  const upPct = market.totalPool > 0n ? Number(market.totalUp * 100n / market.totalPool) : 50
  const downPct = market.totalPool > 0n ? 100 - upPct : 50

  const hasPosition = position && position.amount > 0n
  const userSide = position?.side === 1 ? 'UP' : position?.side === 2 ? 'DOWN' : null
  const canClaim = isResolved && hasPosition && !position?.claimed

  function handleBet(isUp: boolean) {
    if (!betAmount || !address) return
    const amount = parseUnits(betAmount, 6)
    setBetSide(isUp)
    approve({
      address: USDC_ADDRESS,
      abi: USDC_ABI,
      functionName: 'approve',
      args: [BANKR_BETS_ADDRESS, amount],
    })
  }

  return (
    <div className="border border-[rgba(212,208,200,0.1)] p-5 mb-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-3">
          <span className="mono text-xs text-amber">#{marketId.toString()}</span>
          <span className="mono text-sm font-bold text-teal">{DURATION_LABELS[market.duration] || '?'}</span>
        </div>
        <div className="mono text-xs">
          {isResolved ? (
            <span className={market.outcome === 1 ? 'text-green-400' : market.outcome === 2 ? 'text-red-400' : 'text-amber'}>
              {OUTCOME_LABELS[market.outcome]}
            </span>
          ) : (
            <span className="text-chrome">{timeLeft(closeTime)}</span>
          )}
        </div>
      </div>

      <div className="mb-3">
        <div className="flex justify-between mono text-xs mb-1">
          <span className="text-green-400">UP {upPct}%</span>
          <span className="text-red-400">{downPct}% DOWN</span>
        </div>
        <div className="flex h-2 bg-[rgba(212,208,200,0.05)] overflow-hidden">
          <div className="bg-green-400/30 transition-all" style={{ width: `${upPct}%` }} />
          <div className="bg-red-400/30 transition-all" style={{ width: `${downPct}%` }} />
        </div>
        <div className="flex justify-between mono text-xs mt-1 text-muted">
          <span>{formatUSDC(market.totalUp)}</span>
          <span>Pool: {formatUSDC(market.totalPool)}</span>
          <span>{formatUSDC(market.totalDown)}</span>
        </div>
      </div>

      {hasPosition && (
        <div className="mono text-xs p-2 mb-3 border border-[rgba(212,208,200,0.05)] bg-[rgba(212,208,200,0.02)]">
          Your bet: {formatUSDC(position!.amount)} {userSide}
          {position?.isAgent && <span className="text-teal ml-2">[AGENT]</span>}
          {position?.claimed && <span className="text-muted ml-2">[CLAIMED]</span>}
        </div>
      )}

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
          <button className="btn btn-up" onClick={() => handleBet(true)} disabled={!!approveTx || betting}>
            {approveTx || betting ? '...' : 'UP'}
          </button>
          <button className="btn btn-down" onClick={() => handleBet(false)} disabled={!!approveTx || betting}>
            {approveTx || betting ? '...' : 'DOWN'}
          </button>
        </div>
      )}

      {canClaim && (
        <button className="btn btn-primary w-full mt-2" onClick={() => claimWinnings({
          address: BANKR_BETS_ADDRESS,
          abi: BANKR_BETS_ABI,
          functionName: 'claim',
          args: [marketId],
        })} disabled={claiming}>
          {claiming ? 'CLAIMING...' : 'CLAIM'}
        </button>
      )}
    </div>
  )
}

function TestnetFaucet() {
  const { address } = useAccount()
  const { writeContract: mint, data: mintTx } = useWriteContract()
  const { isLoading: minting } = useWaitForTransactionReceipt({ hash: mintTx })

  if (!address) return null

  return (
    <div className="border border-[rgba(212,208,200,0.05)] p-4 mb-6 bg-[rgba(212,208,200,0.02)]">
      <p className="mono text-xs text-amber mb-2">TESTNET FAUCET</p>
      <p className="text-sm text-muted mb-3">Get mock USDC to place bets on Base Sepolia.</p>
      <button className="btn" onClick={() => mint({
        address: USDC_ADDRESS,
        abi: USDC_ABI,
        functionName: 'mint',
        args: [address, parseUnits('10000', 6)],
      })} disabled={minting}>
        {minting ? 'MINTING...' : 'MINT 10,000 USDC'}
      </button>
    </div>
  )
}

export default function Home() {
  const { data: nextId } = useReadContract({
    address: BANKR_BETS_ADDRESS,
    abi: BANKR_BETS_ABI,
    functionName: 'nextMarketId',
    query: { refetchInterval: 5000 },
  })

  const marketCount = nextId ? Number(nextId) - 1 : 0
  const marketIds = Array.from({ length: marketCount }, (_, i) => BigInt(i + 1)).reverse()

  return (
    <div className="max-w-[720px] mx-auto px-5 pb-16">
      <Header />

      <div className="mt-8 mb-6">
        <h2>Markets</h2>
        <p className="text-sm text-muted mt-1">
          Bet UP or DOWN on Bankr ecosystem token prices. Winners split the pot.
        </p>
      </div>

      <TestnetFaucet />

      {marketCount === 0 ? (
        <div className="text-center py-12 text-muted">
          <p className="mono text-sm">NO ACTIVE MARKETS</p>
          <p className="text-xs mt-2">The keeper bot creates markets on a schedule. Check back soon.</p>
        </div>
      ) : (
        marketIds.map((id) => <MarketCard key={id.toString()} marketId={id} />)
      )}

      <footer className="mt-16 pt-6 border-t border-[rgba(212,208,200,0.05)] text-center">
        <p className="mono text-xs" style={{ color: 'var(--text-dim)' }}>
          Built by{' '}
          <a href="https://0xsmcai.github.io/" target="_blank" rel="noopener">0xSMC</a>
          {' | '}
          <a href="https://github.com/0xsmcai/bankr-bets" target="_blank" rel="noopener">GitHub</a>
          {' | '}
          <a href={`${BLOCK_EXPLORER}/address/${BANKR_BETS_ADDRESS}`} target="_blank" rel="noopener">Contract</a>
        </p>
        <p className="mono text-xs mt-2" style={{ color: 'var(--text-dim)' }}>
          TESTNET ONLY. Not audited. Not financial advice. Use at your own risk.
        </p>
      </footer>
    </div>
  )
}
