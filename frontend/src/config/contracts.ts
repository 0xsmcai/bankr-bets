// Testnet deployment addresses (Base Sepolia)
export const BANKR_BETS_ADDRESS = '0x51187AFB8477AdC06C0ba8DA4b2e1c905f7703A3' as `0x${string}`
export const USDC_ADDRESS = '0x61373Fb7eaefb9463d1BaAF7b7c47ed0E68C26f6' as `0x${string}`
export const CHAIN_ID = 84532
export const BLOCK_EXPLORER = 'https://base-sepolia.blockscout.com'

export const USDC_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'mint',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [],
  },
] as const

export const BANKR_BETS_ABI = [
  // View functions
  {
    name: 'getMarket',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'token', type: 'address' },
        { name: 'pool', type: 'address' },
        { name: 'isToken0', type: 'bool' },
        { name: 'duration', type: 'uint8' },
        { name: 'openTime', type: 'uint48' },
        { name: 'closeTime', type: 'uint48' },
        { name: 'bettingDeadline', type: 'uint48' },
        { name: 'openingTick', type: 'int24' },
        { name: 'outcome', type: 'uint8' },
        { name: 'totalUp', type: 'uint128' },
        { name: 'totalDown', type: 'uint128' },
        { name: 'totalPool', type: 'uint128' },
        { name: 'resolved', type: 'bool' },
      ],
    }],
  },
  {
    name: 'getPosition',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'user', type: 'address' },
    ],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'amount', type: 'uint128' },
        { name: 'side', type: 'uint8' },
        { name: 'claimed', type: 'bool' },
        { name: 'isAgent', type: 'bool' },
      ],
    }],
  },
  {
    name: 'nextMarketId',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'activeMarketIds',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256[]' }],
  },
  {
    name: 'userExposure',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  // Write functions
  {
    name: 'bet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'marketId', type: 'uint256' },
      { name: 'isUp', type: 'bool' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'claim',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'marketId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  // Events
  {
    name: 'BetPlaced',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'bettor', type: 'address', indexed: true },
      { name: 'isUp', type: 'bool', indexed: false },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'isAgent', type: 'bool', indexed: false },
    ],
  },
  {
    name: 'MarketResolved',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'outcome', type: 'uint8', indexed: false },
      { name: 'closingTick', type: 'int24', indexed: false },
    ],
  },
  {
    name: 'Claimed',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'bettor', type: 'address', indexed: true },
      { name: 'payout', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'MarketCreated',
    type: 'event',
    inputs: [
      { name: 'marketId', type: 'uint256', indexed: true },
      { name: 'token', type: 'address', indexed: true },
      { name: 'duration', type: 'uint8', indexed: false },
      { name: 'openTime', type: 'uint48', indexed: false },
      { name: 'closeTime', type: 'uint48', indexed: false },
      { name: 'openingTick', type: 'int24', indexed: false },
    ],
  },
] as const
