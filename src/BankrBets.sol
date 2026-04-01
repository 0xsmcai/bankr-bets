// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BankrBets — Parimutuel Binary Prediction Market on Base
/// @notice Players bet UP or DOWN on DRB/BNKR price. Winners split the pot.
/// @dev Hybrid oracle: Uniswap V3 TWAP + keeper-submitted last-swap tick.
///      Security: OZ v5.1+ ReentrancyGuardTransient, SafeERC20, Math.mulDiv.
///      Patterns from: PoolTogether V5 (claim), Gnosis CTF (payout math), Thales (market isolation).

// ── Interfaces ────────────────────────────────────────────────────

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

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

interface IIdentityRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

// ── Contract ──────────────────────────────────────────────────────

contract BankrBets is Ownable2Step, ReentrancyGuardTransient, Pausable {
    using SafeERC20 for IERC20;

    // ── Types ─────────────────────────────────────────────────────

    enum Outcome { PENDING, UP, DOWN, VOIDED }

    enum Duration { ONE_HOUR, FOUR_HOUR, DAILY }

    struct TokenConfig {
        IUniswapV3Pool pool;
        bool isToken0;       // true if the betting token is token0 in the pool
        bool active;
    }

    struct Market {
        address token;           // betting token address (DRB or BNKR)
        address pool;            // snapshotted pool address at creation (Codex Finding #3)
        bool isToken0;           // snapshotted at creation
        Duration duration;
        uint48 openTime;
        uint48 closeTime;
        uint48 bettingDeadline;  // closeTime - TWAP window
        int24 openingTick;       // TWAP at market open
        Outcome outcome;
        uint128 totalUp;         // total USDC bet on UP
        uint128 totalDown;       // total USDC bet on DOWN
        uint128 totalPool;       // totalUp + totalDown
        bool resolved;
    }

    struct UserPosition {
        uint128 amount;
        uint8 side;        // 0 = no bet, 1 = UP, 2 = DOWN
        bool claimed;
        bool isAgent;
    }

    // ── Constants ─────────────────────────────────────────────────

    uint256 public constant MIN_BET = 1e6;           // 1 USDC
    uint256 public constant MAX_BET = 1_000e6;       // $1,000
    uint256 public constant MAX_MARKET = 10_000e6;   // $10,000 per market
    uint256 public constant MAX_USER = 5_000e6;      // $5,000 per user across all markets
    uint256 public constant MAX_DAILY = 30_000e6;    // $30,000 protocol-wide daily
    uint256 public constant FEE_BPS = 300;           // 3% (200 treasury + 100 insurance)
    uint256 public constant TREASURY_BPS = 200;
    uint256 public constant GRACE_PERIOD = 2 hours;

    // TWAP windows per duration
    uint32 public constant TWAP_OPEN_1H = 300;       // 5 min
    uint32 public constant TWAP_CLOSE_1H = 900;      // 15 min
    uint32 public constant TWAP_OPEN_4H = 600;       // 10 min
    uint32 public constant TWAP_CLOSE_4H = 1800;     // 30 min
    uint32 public constant TWAP_OPEN_24H = 1800;     // 30 min
    uint32 public constant TWAP_CLOSE_24H = 3600;    // 60 min

    // Divergence threshold: max ticks between TWAP and keeper price
    int24 public constant MAX_TICK_DIVERGENCE = 2000; // ~22% price difference
    uint256 public constant MAX_RESOLUTION_DELAY = 4 hours; // auto-void if not resolved within this

    // Minimum market participation
    uint256 public constant MIN_TOTAL = 100e6;       // $100 total
    uint256 public constant MIN_PER_SIDE = 50e6;     // $50 per side
    uint256 public constant MIN_PARTICIPANTS = 2;

    // ── State ─────────────────────────────────────────────────────

    IERC20 public immutable usdc;
    IIdentityRegistry public immutable agentRegistry;

    address public keeper;
    address public treasury;
    address public insuranceFund;

    uint256 public nextMarketId = 1;
    uint256 public dailyVolume;
    uint256 public dailyVolumeResetTime;

    mapping(address => TokenConfig) public tokens;
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => UserPosition)) public positions;
    mapping(uint256 => uint256) public marketParticipants; // unique bettor count
    mapping(uint256 => mapping(address => bool)) public hasBet; // dedup for participant count
    mapping(address => uint256) public userExposure; // total active bets across all markets
    mapping(uint256 => bool) public feesDistributed; // prevent double fee distribution

    // ── Events ────────────────────────────────────────────────────

    event MarketCreated(
        uint256 indexed marketId, address indexed token, Duration duration,
        uint48 openTime, uint48 closeTime, int24 openingTick
    );
    event BetPlaced(
        uint256 indexed marketId, address indexed bettor,
        bool isUp, uint256 amount, bool isAgent
    );
    event MarketResolved(
        uint256 indexed marketId, Outcome outcome, int24 closingTick
    );
    event Claimed(
        uint256 indexed marketId, address indexed bettor, uint256 payout
    );
    event EmergencyWithdrawal(
        uint256 indexed marketId, address indexed bettor, uint256 amount
    );
    event FeesDistributed(uint256 treasuryAmount, uint256 insuranceAmount);
    event KeeperUpdated(address indexed newKeeper);
    event TokenAdded(address indexed token, address pool, bool isToken0);
    event TokenRemoved(address indexed token);

    // ── Errors ────────────────────────────────────────────────────

    error NotKeeper();
    error TokenNotActive();
    error MarketNotPending();
    error MarketNotResolved();
    error BettingClosed();
    error BetTooSmall();
    error BetTooLarge();
    error MarketCapExceeded();
    error UserCapExceeded();
    error DailyCapExceeded();
    error AlreadyClaimed();
    error NotWinner();
    error NoBet();
    error NotVoidedOrUnresolved();
    error GracePeriodNotElapsed();
    error MarketAlreadyResolved();
    error OracleError();
    error OracleDivergence();
    error MinimumNotMet();
    error MarketNotClosed();
    error CannotSwitchSides();
    error FeesAlreadyDistributed();
    error ZeroAddress();

    // ── Modifiers ─────────────────────────────────────────────────

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    // ── Constructor ───────────────────────────────────────────────

    constructor(
        address _usdc,
        address _agentRegistry,
        address _keeper,
        address _treasury,
        address _insuranceFund,
        address _admin
    ) Ownable(_admin) {
        if (_usdc == address(0) || _keeper == address(0) || _treasury == address(0)
            || _insuranceFund == address(0) || _admin == address(0)) revert ZeroAddress();
        usdc = IERC20(_usdc);
        agentRegistry = IIdentityRegistry(_agentRegistry);
        keeper = _keeper;
        treasury = _treasury;
        insuranceFund = _insuranceFund;
    }

    // ── Admin ─────────────────────────────────────────────────────

    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function addToken(address token, address pool, bool isToken0) external onlyOwner {
        if (token == address(0) || pool == address(0)) revert ZeroAddress();
        tokens[token] = TokenConfig(IUniswapV3Pool(pool), isToken0, true);
        emit TokenAdded(token, pool, isToken0);
    }

    function removeToken(address token) external onlyOwner {
        tokens[token].active = false;
        emit TokenRemoved(token);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Admin can void a specific market (e.g., detected oracle manipulation mid-market)
    function voidMarket(uint256 marketId) external onlyOwner {
        Market storage m = markets[marketId];
        if (m.resolved) revert MarketAlreadyResolved();
        _voidMarket(m, marketId);
    }

    // ── Keeper: Create Market ─────────────────────────────────────

    function createMarket(address token, Duration duration)
        external
        onlyKeeper
        whenNotPaused
        returns (uint256 marketId)
    {
        TokenConfig storage tc = tokens[token];
        if (!tc.active) revert TokenNotActive();

        (uint32 openWindow, uint32 closeWindow) = _twapWindows(duration);
        uint48 openTime = uint48(block.timestamp);
        uint48 closeTime = openTime + _durationSeconds(duration);
        uint48 bettingDeadline = closeTime - uint48(closeWindow);

        // Read opening TWAP
        int24 openingTick = _readTwap(tc.pool, openWindow);

        marketId = nextMarketId++;
        markets[marketId] = Market({
            token: token,
            pool: address(tc.pool),
            isToken0: tc.isToken0,
            duration: duration,
            openTime: openTime,
            closeTime: closeTime,
            bettingDeadline: bettingDeadline,
            openingTick: openingTick,
            outcome: Outcome.PENDING,
            totalUp: 0,
            totalDown: 0,
            totalPool: 0,
            resolved: false
        });

        emit MarketCreated(marketId, token, duration, openTime, closeTime, openingTick);
    }

    // ── Public: Bet ───────────────────────────────────────────────

    function bet(uint256 marketId, bool isUp, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        Market storage m = markets[marketId];
        if (m.outcome != Outcome.PENDING) revert MarketNotPending();
        if (block.timestamp >= m.bettingDeadline) revert BettingClosed();

        if (amount < MIN_BET) revert BetTooSmall();
        if (amount > MAX_BET) revert BetTooLarge();

        // Cap checks
        if (uint256(m.totalPool) + amount > MAX_MARKET) revert MarketCapExceeded();
        if (userExposure[msg.sender] + amount > MAX_USER) revert UserCapExceeded();
        _checkDailyCap(amount);

        // Effects before interactions (CEI pattern from PoolTogether V5)
        UserPosition storage pos = positions[marketId][msg.sender];
        // Allow multiple bets on same side, reject switching sides
        if (pos.side != 0 && pos.side != (isUp ? 1 : 2)) revert CannotSwitchSides();
        pos.amount += uint128(amount);
        pos.side = isUp ? 1 : 2;

        if (isUp) {
            m.totalUp += uint128(amount);
        } else {
            m.totalDown += uint128(amount);
        }
        m.totalPool += uint128(amount);
        userExposure[msg.sender] += amount;

        // Track unique participants
        if (!hasBet[marketId][msg.sender]) {
            hasBet[marketId][msg.sender] = true;
            marketParticipants[marketId]++;
        }

        // Agent tagging — try/catch so registry failure doesn't block betting
        bool isAgent = _checkAgent(msg.sender);
        pos.isAgent = isAgent;

        // Interaction: transfer USDC (last, per CEI)
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit BetPlaced(marketId, msg.sender, isUp, amount, isAgent);
    }

    // ── Keeper: Resolve ───────────────────────────────────────────

    function resolve(uint256 marketId, int24 offChainTick)
        external
        onlyKeeper
        nonReentrant
    {
        Market storage m = markets[marketId];
        if (m.resolved) revert MarketAlreadyResolved();
        if (m.outcome != Outcome.PENDING) revert MarketNotPending();
        if (block.timestamp < m.closeTime) revert MarketNotClosed();

        // Auto-void if resolution is too late (ethskills Finding 3A)
        if (block.timestamp > m.closeTime + MAX_RESOLUTION_DELAY) {
            _voidMarket(m, marketId);
            return;
        }

        // Check minimum participation
        if (m.totalPool < MIN_TOTAL || m.totalUp < MIN_PER_SIDE
            || m.totalDown < MIN_PER_SIDE || marketParticipants[marketId] < MIN_PARTICIPANTS)
        {
            _voidMarket(m, marketId);
            return;
        }

        // Read closing TWAP using snapshotted pool (not live config)
        (, uint32 closeWindow) = _twapWindows(m.duration);
        int24 closingTick = _readTwap(IUniswapV3Pool(m.pool), closeWindow);

        // Hybrid oracle: check divergence between TWAP and keeper's off-chain tick
        int24 divergence = closingTick > offChainTick
            ? closingTick - offChainTick
            : offChainTick - closingTick;
        if (divergence > MAX_TICK_DIVERGENCE) revert OracleDivergence();

        // Determine outcome using TWAP (the trusted source)
        _resolveWithTick(m, marketId, closingTick);
    }

    /// @notice Permissionless TWAP-only resolution after grace period (keeper down fallback)
    /// @dev TWAP reads the window ending at block.timestamp, not at closeTime.
    ///      This means late resolution uses post-close price data. The keeper SHOULD
    ///      resolve ASAP after closeTime. resolveByTwap is a safety net for keeper
    ///      downtime — the TWAP quality degrades with delay, but MAX_RESOLUTION_DELAY
    ///      auto-voids if too late. This is an accepted architectural trade-off.
    function resolveByTwap(uint256 marketId) external nonReentrant {
        Market storage m = markets[marketId];
        if (m.resolved) revert MarketAlreadyResolved();
        if (m.outcome != Outcome.PENDING) revert MarketNotPending();
        if (block.timestamp < m.closeTime + GRACE_PERIOD) revert GracePeriodNotElapsed();

        // Auto-void if too late (ethskills Finding 3A — prevents exploiting stale TWAP)
        if (block.timestamp > m.closeTime + MAX_RESOLUTION_DELAY) {
            _voidMarket(m, marketId);
            return;
        }

        // Check minimums
        if (m.totalPool < MIN_TOTAL || m.totalUp < MIN_PER_SIDE
            || m.totalDown < MIN_PER_SIDE || marketParticipants[marketId] < MIN_PARTICIPANTS)
        {
            _voidMarket(m, marketId);
            return;
        }

        (, uint32 closeWindow) = _twapWindows(m.duration);
        int24 closingTick = _readTwap(IUniswapV3Pool(m.pool), closeWindow);

        _resolveWithTick(m, marketId, closingTick);
    }

    // ── Public: Claim ─────────────────────────────────────────────

    function claim(uint256 marketId) external nonReentrant returns (uint256 payout) {
        Market storage m = markets[marketId];
        if (!m.resolved) revert MarketNotResolved();

        UserPosition storage pos = positions[marketId][msg.sender];
        if (pos.claimed) revert AlreadyClaimed();
        if (pos.amount == 0) revert NoBet();

        if (m.outcome == Outcome.VOIDED) {
            // Voided: return original deposit, no fees
            payout = pos.amount;
        } else {
            bool isWinner = (m.outcome == Outcome.UP && pos.side == 1)
                         || (m.outcome == Outcome.DOWN && pos.side == 2);
            if (isWinner) {
                // Payout math: Math.mulDiv for 512-bit precision (from Gnosis CTF pattern)
                uint256 totalWinning = m.outcome == Outcome.UP ? m.totalUp : m.totalDown;
                uint256 distributable = Math.mulDiv(m.totalPool, 10_000 - FEE_BPS, 10_000);
                payout = Math.mulDiv(distributable, pos.amount, totalWinning);
            } else {
                // Loser: payout = 0, but we still clear their exposure
                payout = 0;
            }
        }

        // Effects before interactions (PoolTogether V5 claim pattern)
        pos.claimed = true;
        userExposure[msg.sender] -= pos.amount;

        // Interaction last — skip zero transfer for losers (saves gas)
        if (payout > 0) {
            usdc.safeTransfer(msg.sender, payout);
        }

        emit Claimed(marketId, msg.sender, payout);
    }

    // ── Public: Emergency Withdraw ────────────────────────────────

    /// @notice Returns original deposit when market is unresolved and paused or past grace period
    function emergencyWithdraw(uint256 marketId) external nonReentrant {
        Market storage m = markets[marketId];

        // If market is already voided, allow claim-style withdrawal
        if (m.resolved && m.outcome == Outcome.VOIDED) {
            // Fall through to withdrawal logic below
        } else if (m.resolved) {
            revert MarketAlreadyResolved(); // use claim() for resolved markets
        } else {
            // Unresolved market: only allow withdrawal past MAX_RESOLUTION_DELAY.
            // Pause does NOT unlock early withdrawal — prevents race with resolution.
            // (Codex Cycle 3: pause + emergencyWithdraw was still raceable)
            bool isPastMaxDelay = block.timestamp > m.closeTime + MAX_RESOLUTION_DELAY;
            if (!isPastMaxDelay) revert NotVoidedOrUnresolved();

            // Void the market (safe now — resolution window has fully expired)
            if (m.outcome == Outcome.PENDING) {
                _voidMarket(m, marketId);
            }
        }

        UserPosition storage pos = positions[marketId][msg.sender];
        if (pos.amount == 0) revert NoBet();
        if (pos.claimed) revert AlreadyClaimed();

        uint256 deposit = pos.amount;

        // Effects before interactions
        pos.claimed = true;
        pos.amount = 0;
        userExposure[msg.sender] -= deposit;

        // Interaction last
        usdc.safeTransfer(msg.sender, deposit);

        emit EmergencyWithdrawal(marketId, msg.sender, deposit);
    }

    // ── Admin: Distribute Fees ────────────────────────────────────

    /// @notice Distributes accumulated fees from resolved markets
    function distributeFees(uint256 marketId) external nonReentrant {
        Market storage m = markets[marketId];
        if (!m.resolved || m.outcome == Outcome.VOIDED) return;
        if (feesDistributed[marketId]) revert FeesAlreadyDistributed();
        feesDistributed[marketId] = true;

        uint256 fee = Math.mulDiv(m.totalPool, FEE_BPS, 10_000);
        uint256 treasuryShare = Math.mulDiv(fee, TREASURY_BPS, FEE_BPS);
        uint256 insuranceShare = fee - treasuryShare;

        // Fees stay in contract until explicitly distributed
        // This prevents fee distribution from affecting solvency of unresolved markets
        usdc.safeTransfer(treasury, treasuryShare);
        usdc.safeTransfer(insuranceFund, insuranceShare);

        emit FeesDistributed(treasuryShare, insuranceShare);
    }

    // ── View Functions ────────────────────────────────────────────

    function getMarket(uint256 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    function getPosition(uint256 marketId, address user) external view returns (UserPosition memory) {
        return positions[marketId][user];
    }

    function activeMarketIds() external view returns (uint256[] memory) {
        // Simple linear scan — acceptable for <100 active markets
        uint256 count;
        for (uint256 i = 1; i < nextMarketId; i++) {
            if (!markets[i].resolved && markets[i].openTime > 0) count++;
        }
        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i = 1; i < nextMarketId; i++) {
            if (!markets[i].resolved && markets[i].openTime > 0) ids[idx++] = i;
        }
        return ids;
    }

    // ── Internal ──────────────────────────────────────────────────

    function _resolveWithTick(Market storage m, uint256 marketId, int24 closingTick) internal {
        if (closingTick == m.openingTick) {
            _voidMarket(m, marketId);
        } else {
            bool isToken0 = m.isToken0; // use snapshotted value
            // For token0: tick up = price up. For token1: tick up = price down.
            bool priceUp = isToken0 ? (closingTick > m.openingTick) : (closingTick < m.openingTick);
            m.outcome = priceUp ? Outcome.UP : Outcome.DOWN;
            m.resolved = true;
            emit MarketResolved(marketId, m.outcome, closingTick);
        }
    }

    function _voidMarket(Market storage m, uint256 marketId) internal {
        m.outcome = Outcome.VOIDED;
        m.resolved = true;
        emit MarketResolved(marketId, Outcome.VOIDED, 0);
    }

    function _readTwap(IUniswapV3Pool pool, uint32 window) internal view returns (int24) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;

        try pool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory
        ) {
            int56 tickDiff = tickCumulatives[1] - tickCumulatives[0];
            int24 avgTick = int24(tickDiff / int56(uint56(window)));
            // Round toward negative infinity (Uniswap convention)
            if (tickDiff < 0 && (tickDiff % int56(uint56(window)) != 0)) {
                avgTick--;
            }
            return avgTick;
        } catch {
            revert OracleError();
        }
    }

    function _checkAgent(address user) internal view returns (bool) {
        try agentRegistry.balanceOf(user) returns (uint256 bal) {
            return bal > 0;
        } catch {
            return false;
        }
    }

    function _checkDailyCap(uint256 amount) internal {
        if (block.timestamp >= dailyVolumeResetTime + 1 days) {
            dailyVolume = 0;
            dailyVolumeResetTime = block.timestamp;
        }
        if (dailyVolume + amount > MAX_DAILY) revert DailyCapExceeded();
        dailyVolume += amount;
    }

    function _twapWindows(Duration d) internal pure returns (uint32 openWindow, uint32 closeWindow) {
        if (d == Duration.ONE_HOUR) return (TWAP_OPEN_1H, TWAP_CLOSE_1H);
        if (d == Duration.FOUR_HOUR) return (TWAP_OPEN_4H, TWAP_CLOSE_4H);
        return (TWAP_OPEN_24H, TWAP_CLOSE_24H);
    }

    function _durationSeconds(Duration d) internal pure returns (uint48) {
        if (d == Duration.ONE_HOUR) return 1 hours;
        if (d == Duration.FOUR_HOUR) return 4 hours;
        return 24 hours;
    }
}
