// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title BankrBets — P2P Binary Prediction Market for AI Agents
/// @notice ERC-8004 gated. Agents bet USDC on Bankr token price direction.
/// @dev V0: BNKR only, 1-hour expiry, 50/50 odds, $100 max bet.
///      Settlement via Uniswap V3 TWAP (30-min window, flash-loan resistant).

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

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
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
        int24 strikeTick;       // Uniswap V3 tick at creation
        uint256 expiry;
        Status status;
        address winner;
    }

    // ── Constants ──────────────────────────────────────────────
    uint256 public constant MAX_BET = 100e6;       // 100 USDC (6 decimals)
    uint256 public constant MIN_BET = 1e6;         // 1 USDC
    uint256 public constant EXPIRY_DURATION = 1 hours;
    uint32 public constant TWAP_WINDOW = 30 minutes;
    uint256 public constant SETTLEMENT_DEADLINE = 2 hours; // max time after expiry to settle

    // ── Immutables ─────────────────────────────────────────────
    IERC20 public immutable usdc;
    IIdentityRegistry public immutable registry;
    IUniswapV3Pool public immutable bnkrPool;
    address public immutable feeRecipient;
    bool public immutable bnkrIsToken0;

    // ── State ──────────────────────────────────────────────────
    uint256 public constant PROTOCOL_FEE_BPS = 100;  // 1%
    uint256 public accumulatedFees;
    uint256 public nextBetId = 1;
    mapping(uint256 => Bet) public bets;

    // ── Events ─────────────────────────────────────────────────
    event BetCreated(
        uint256 indexed betId,
        address indexed creator,
        Direction direction,
        uint256 amount,
        int24 strikeTick,
        uint256 expiry
    );
    event BetTaken(uint256 indexed betId, address indexed taker);
    event BetSettled(uint256 indexed betId, address indexed winner, uint256 payout, int24 settlementTick);
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
    error BetExpired();
    error SettlementWindowExpired();
    error InvalidConstructorAddress();

    // ── Constructor ────────────────────────────────────────────
    constructor(
        address _usdc,
        address _registry,
        address _bnkrPool,
        address _feeRecipient,
        bool _bnkrIsToken0
    ) {
        if (_usdc == address(0)) revert InvalidConstructorAddress();
        if (_registry == address(0)) revert InvalidConstructorAddress();
        if (_bnkrPool == address(0)) revert InvalidConstructorAddress();
        if (_feeRecipient == address(0)) revert InvalidConstructorAddress();
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

        // Use TWAP tick as strike for oracle consistency with settlement
        // Prevents single-block spot manipulation at creation time
        int24 currentTick = _getTwapTick();

        betId = nextBetId++;
        uint256 expiry = block.timestamp + EXPIRY_DURATION;

        bets[betId] = Bet({
            creator: msg.sender,
            taker: address(0),
            creatorDirection: direction,
            amount: amount,
            strikeTick: currentTick,
            expiry: expiry,
            status: Status.OPEN,
            winner: address(0)
        });

        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        emit BetCreated(betId, msg.sender, direction, amount, currentTick, expiry);
    }

    /// @notice Take the opposite side of an open bet
    /// @param betId The bet to take
    function takeBet(uint256 betId) external onlyRegistered nonReentrant {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status != Status.OPEN) revert BetNotOpen();
        if (block.timestamp >= bet.expiry) revert BetExpired();
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
        if (block.timestamp > bet.expiry + SETTLEMENT_DEADLINE) revert SettlementWindowExpired();

        // Read TWAP tick — resistant to flash-loan manipulation
        int24 settlementTick = _getTwapTick();

        uint256 pot = bet.amount * 2;
        uint256 fee = (pot * PROTOCOL_FEE_BPS) / 10000;
        uint256 payout = pot - fee;
        accumulatedFees += fee;

        if (settlementTick == bet.strikeTick) {
            // Draw — exact same tick, return stakes minus fee split
            uint256 halfPayout = payout / 2;
            uint256 dust = payout - (halfPayout * 2);
            accumulatedFees += dust; // recover truncation dust
            bet.status = Status.SETTLED;
            bet.winner = address(0); // draw
            if (!usdc.transfer(bet.creator, halfPayout)) revert TransferFailed();
            if (!usdc.transfer(bet.taker, halfPayout)) revert TransferFailed();
            emit BetSettled(betId, address(0), halfPayout, settlementTick);
            return;
        }

        // Determine if BNKR price went up
        // Tick represents log1.0001(token1/token0)
        // If BNKR is token0: higher tick = more token1 per token0 = more WETH per BNKR = BNKR UP
        // If BNKR is token1: higher tick = more BNKR per WETH = BNKR DOWN
        bool priceWentUp = bnkrIsToken0
            ? (settlementTick > bet.strikeTick)
            : (settlementTick < bet.strikeTick);

        address winner;
        if (priceWentUp) {
            winner = (bet.creatorDirection == Direction.LONG) ? bet.creator : bet.taker;
        } else {
            winner = (bet.creatorDirection == Direction.SHORT) ? bet.creator : bet.taker;
        }

        bet.status = Status.SETTLED;
        bet.winner = winner;

        if (!usdc.transfer(winner, payout)) revert TransferFailed();

        emit BetSettled(betId, winner, payout, settlementTick);
    }

    /// @notice Cancel an unmatched bet. Only creator, only if OPEN.
    /// @param betId The bet to cancel
    function cancelBet(uint256 betId) external nonReentrant {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status == Status.CANCELLED) revert BetAlreadyCancelled();
        if (bet.status != Status.OPEN) revert BetNotOpen();
        if (msg.sender != bet.creator) revert OnlyCreatorCanCancel();

        bet.status = Status.CANCELLED;

        if (!usdc.transfer(bet.creator, bet.amount)) revert TransferFailed();

        emit BetCancelled(betId);
    }

    /// @notice Emergency refund for active bets that passed the settlement deadline
    ///         (e.g., TWAP oracle failure). Returns stakes to both parties minus fee.
    function emergencyRefund(uint256 betId) external nonReentrant {
        Bet storage bet = bets[betId];
        if (bet.creator == address(0)) revert BetNotFound();
        if (bet.status != Status.ACTIVE) revert BetNotActive();
        if (block.timestamp <= bet.expiry + SETTLEMENT_DEADLINE) revert BetNotExpired();

        uint256 pot = bet.amount * 2;
        uint256 fee = (pot * PROTOCOL_FEE_BPS) / 10000;
        uint256 refundPerSide = (pot - fee) / 2;
        uint256 dust = (pot - fee) - (refundPerSide * 2);
        accumulatedFees += fee + dust;

        bet.status = Status.CANCELLED;
        if (!usdc.transfer(bet.creator, refundPerSide)) revert TransferFailed();
        if (!usdc.transfer(bet.taker, refundPerSide)) revert TransferFailed();
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

    /// @notice Get current BNKR spot tick from V3 pool
    function getCurrentTick() external view returns (int24 tick) {
        (, tick,,,,, ) = bnkrPool.slot0();
    }

    /// @notice Get TWAP tick used for settlement
    function getSettlementTick() external view returns (int24) {
        return _getTwapTick();
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
            int24 strikeTick,
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
            bet.strikeTick,
            bet.expiry,
            bet.status,
            bet.winner
        );
    }

    // ── Internal ───────────────────────────────────────────────

    /// @dev Compute 30-minute TWAP tick from Uniswap V3 pool.
    ///      Resistant to flash-loan oracle manipulation.
    function _getTwapTick() internal view returns (int24) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_WINDOW;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = bnkrPool.observe(secondsAgos);

        int56 tickDiff = tickCumulatives[1] - tickCumulatives[0];
        int56 window = int56(uint56(TWAP_WINDOW));
        int24 averageTick = int24(tickDiff / window);

        // Round towards negative infinity (Uniswap convention)
        if (tickDiff < 0 && (tickDiff % window != 0)) {
            averageTick--;
        }

        return averageTick;
    }

    /// @dev Check if address is a registered ERC-8004 agent
    ///      V0: balanceOf check with ownerOf fallback for known IDs.
    ///      Production: use proper enumeration or off-chain attestation.
    function _isRegistered(address addr) internal view returns (bool) {
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
