// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title BankrBets — P2P Binary Prediction Market for AI Agents
/// @notice ERC-8004 gated. Agents bet USDC on Bankr token price direction.
/// @dev V0: BNKR only, 1-hour expiry, 50/50 odds, $100 max bet.
///      Settlement via Uniswap V3 spot price (BNKR/WETH pool).

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IIdentityRegistry {
    function ownerOf(uint256 agentId) external view returns (address);
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

/// @dev Minimal reentrancy guard inlined to avoid external dependency
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract BankrBets is ReentrancyGuard {
    // ── Types ──────────────────────────────────────────────────
    enum Direction { LONG, SHORT }
    enum Status { OPEN, ACTIVE, SETTLED, CANCELLED }

    struct Bet {
        address creator;
        address taker;
        Direction creatorDirection;
        uint256 amount;
        uint160 strikePrice;    // sqrtPriceX96 at creation
        uint256 expiry;
        Status status;
        address winner;
    }

    // ── Constants ──────────────────────────────────────────────
    uint256 public constant MAX_BET = 100e6;       // 100 USDC (6 decimals)
    uint256 public constant MIN_BET = 1e6;         // 1 USDC
    uint256 public constant EXPIRY_DURATION = 1 hours;

    // ── Immutables ─────────────────────────────────────────────
    IERC20 public immutable usdc;
    IIdentityRegistry public immutable registry;
    IUniswapV3Pool public immutable bnkrPool;
    address public immutable feeRecipient;
    bool public immutable bnkrIsToken0;

    // ── State ──────────────────────────────────────────────────
    uint256 public protocolFeeBps = 100;  // 1%
    uint256 public accumulatedFees;
    uint256 public nextBetId = 1;
    mapping(uint256 => Bet) public bets;

    // ── Events ─────────────────────────────────────────────────
    event BetCreated(
        uint256 indexed betId,
        address indexed creator,
        Direction direction,
        uint256 amount,
        uint160 strikePrice,
        uint256 expiry
    );
    event BetTaken(uint256 indexed betId, address indexed taker);
    event BetSettled(uint256 indexed betId, address indexed winner, uint256 payout, uint160 settlementPrice);
    event BetCancelled(uint256 indexed betId);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ── Errors ─────────────────────────────────────────────────
    error NotRegisteredAgent();
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error BetNotFound();
    error BetNotOpen();
    error BetNotActive();
    error BetNotExpired();
    error CannotTakeOwnBet();
    error BetAlreadyCancelled();
    error BetAlreadySettled();
    error OnlyCreatorCanCancel();
    error TransferFailed();
    error NoFeesToWithdraw();

    // ── Constructor ────────────────────────────────────────────
    constructor(
        address _usdc,
        address _registry,
        address _bnkrPool,
        address _feeRecipient,
        bool _bnkrIsToken0
    ) {
        usdc = IERC20(_usdc);
        registry = IIdentityRegistry(_registry);
        bnkrPool = IUniswapV3Pool(_bnkrPool);
        feeRecipient = _feeRecipient;
        bnkrIsToken0 = _bnkrIsToken0;
    }

    // ── Modifiers ──────────────────────────────────────────────
    modifier onlyRegistered() {
        if (!_isRegistered(msg.sender)) revert NotRegisteredAgent();
        _;
    }

    // ── Core Functions ─────────────────────────────────────────

    /// @notice Create a new bet on BNKR price direction
    /// @param direction LONG (0) or SHORT (1)
    /// @param amount USDC amount to bet (6 decimals)
    /// @return betId The ID of the created bet
    function createBet(Direction direction, uint256 amount)
        external
        onlyRegistered
        returns (uint256 betId)
    {
        if (amount < MIN_BET) revert BetAmountTooLow();
        if (amount > MAX_BET) revert BetAmountTooHigh();

        // Get current spot price as strike
        (uint160 strikePrice,,,,,, ) = bnkrPool.slot0();

        betId = nextBetId++;
        uint256 expiry = block.timestamp + EXPIRY_DURATION;

        bets[betId] = Bet({
            creator: msg.sender,
            taker: address(0),
            creatorDirection: direction,
            amount: amount,
            strikePrice: strikePrice,
            expiry: expiry,
            status: Status.OPEN,
            winner: address(0)
        });

        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        emit BetCreated(betId, msg.sender, direction, amount, strikePrice, expiry);
    }

    /// @notice Take the opposite side of an open bet
    /// @param betId The bet to take
    function takeBet(uint256 betId) external onlyRegistered {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status != Status.OPEN) revert BetNotOpen();
        if (msg.sender == bet.creator) revert CannotTakeOwnBet();

        bet.taker = msg.sender;
        bet.status = Status.ACTIVE;

        if (!usdc.transferFrom(msg.sender, address(this), bet.amount)) revert TransferFailed();

        emit BetTaken(betId, msg.sender);
    }

    /// @notice Settle a bet after expiry. Anyone can call.
    /// @param betId The bet to settle
    function settle(uint256 betId) external nonReentrant {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status == Status.SETTLED) revert BetAlreadySettled();
        if (bet.status == Status.CANCELLED) revert BetAlreadyCancelled();
        if (bet.status != Status.ACTIVE) revert BetNotActive();
        if (block.timestamp < bet.expiry) revert BetNotExpired();

        // Read current V3 spot price
        (uint160 currentPrice,,,,,, ) = bnkrPool.slot0();

        uint256 pot = bet.amount * 2;
        uint256 fee = (pot * protocolFeeBps) / 10000;
        uint256 payout = pot - fee;
        accumulatedFees += fee;

        if (currentPrice == bet.strikePrice) {
            // Draw — exact same price, return stakes minus fee split
            uint256 halfPayout = payout / 2;
            bet.status = Status.SETTLED;
            bet.winner = address(0); // draw
            if (!usdc.transfer(bet.creator, halfPayout)) revert TransferFailed();
            if (!usdc.transfer(bet.taker, halfPayout)) revert TransferFailed();
            emit BetSettled(betId, address(0), halfPayout, currentPrice);
            return;
        }

        // Determine if BNKR price went up
        // If bnkrIsToken0: higher sqrtPriceX96 = higher token1/token0 = higher WETH/BNKR... wait
        // sqrtPriceX96 = sqrt(token1/token0) * 2^96
        // If BNKR is token0: sqrtPriceX96 = sqrt(WETH/BNKR) — higher means more WETH per BNKR = BNKR UP
        // If BNKR is token1: sqrtPriceX96 = sqrt(BNKR/WETH) — higher means more BNKR per WETH = BNKR DOWN
        bool priceWentUp = bnkrIsToken0
            ? (currentPrice > bet.strikePrice)
            : (currentPrice < bet.strikePrice);

        address winner;
        if (priceWentUp) {
            winner = (bet.creatorDirection == Direction.LONG) ? bet.creator : bet.taker;
        } else {
            winner = (bet.creatorDirection == Direction.SHORT) ? bet.creator : bet.taker;
        }

        bet.status = Status.SETTLED;
        bet.winner = winner;

        if (!usdc.transfer(winner, payout)) revert TransferFailed();

        emit BetSettled(betId, winner, payout, currentPrice);
    }

    /// @notice Cancel an unmatched bet. Only creator, only if OPEN.
    /// @param betId The bet to cancel
    function cancelBet(uint256 betId) external {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status == Status.CANCELLED) revert BetAlreadyCancelled();
        if (bet.status != Status.OPEN) revert BetNotOpen();
        if (msg.sender != bet.creator) revert OnlyCreatorCanCancel();

        bet.status = Status.CANCELLED;

        if (!usdc.transfer(bet.creator, bet.amount)) revert TransferFailed();

        emit BetCancelled(betId);
    }

    /// @notice Withdraw accumulated protocol fees
    function withdrawFees() external {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert NoFeesToWithdraw();
        accumulatedFees = 0;
        if (!usdc.transfer(feeRecipient, amount)) revert TransferFailed();
        emit FeesWithdrawn(feeRecipient, amount);
    }

    // ── View Functions ─────────────────────────────────────────

    /// @notice Get current BNKR spot price from V3 pool
    function getCurrentPrice() external view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,, ) = bnkrPool.slot0();
    }

    /// @notice Get full bet details
    function getBet(uint256 betId)
        external
        view
        returns (
            address creator,
            address taker,
            Direction creatorDirection,
            uint256 amount,
            uint160 strikePrice,
            uint256 expiry,
            Status status,
            address winner
        )
    {
        Bet storage bet = bets[betId];
        return (
            bet.creator,
            bet.taker,
            bet.creatorDirection,
            bet.amount,
            bet.strikePrice,
            bet.expiry,
            bet.status,
            bet.winner
        );
    }

    // ── Internal ───────────────────────────────────────────────

    /// @dev Check if address is a registered ERC-8004 agent
    ///      V0: tries ownerOf for a range of IDs. Simple but works.
    ///      Production: use a proper enumeration or off-chain attestation.
    function _isRegistered(address addr) internal view returns (bool) {
        // Try to call ownerOf — if addr owns any agent, it's registered
        // For V0 we do a simple try/catch on a known range
        // A more robust approach would use a balanceOf-like check
        try registry.ownerOf(0) returns (address) {
            // Registry is callable, now check if addr is registered
            // We use a low-level staticcall approach
        } catch {
            // Registry not available or no agent 0
        }

        // V0 pragmatic approach: check if the address has code OR
        // accept all addresses (with the modifier as a placeholder for mainnet)
        // For testnet, we'll be permissive and check properly on mainnet
        return _checkRegistry(addr);
    }

    function _checkRegistry(address addr) internal view returns (bool) {
        // Try ownerOf for known agent IDs
        // This is a V0 implementation — on mainnet, use proper enumeration
        (bool success, bytes memory data) = address(registry).staticcall(
            abi.encodeWithSignature("balanceOf(address)", addr)
        );
        if (success && data.length >= 32) {
            uint256 balance = abi.decode(data, (uint256));
            return balance > 0;
        }

        // Fallback: check if address is owner of any agent via ownerOf
        // For V0 testing, check a few known IDs
        for (uint256 i = 1; i <= 5; i++) {
            try registry.ownerOf(i) returns (address owner) {
                if (owner == addr) return true;
            } catch {}
        }
        return false;
    }
}
