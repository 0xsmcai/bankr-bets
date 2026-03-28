// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/BankrBets.sol";

/// @dev Mock USDC token for testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "no allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Mock ERC-8004 registry for testing
contract MockRegistry {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    function register(address agent, uint256 agentId) external {
        _owners[agentId] = agent;
        _balances[agent]++;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address owner = _owners[agentId];
        require(owner != address(0), "not registered");
        return owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}

/// @dev Mock V3 pool with configurable tick and TWAP support
contract MockV3Pool {
    int24 public currentTick;
    int56 public tickCumulative0; // cumulative at (now - window)
    int56 public tickCumulative1; // cumulative at now

    function setTick(int24 _tick) external {
        currentTick = _tick;
    }

    /// @dev Set tick cumulatives for TWAP calculation.
    ///      TWAP tick = (cumulative1 - cumulative0) / window
    function setTickCumulatives(int56 _cum0, int56 _cum1) external {
        tickCumulative0 = _cum0;
        tickCumulative1 = _cum1;
    }

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
        )
    {
        return (0, currentTick, 0, 0, 0, 0, true);
    }

    function observe(uint32[] calldata)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0;
        tickCumulatives[1] = tickCumulative1;

        secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        secondsPerLiquidityCumulativeX128s[1] = 0;
    }
}

contract BankrBetsTest is Test {
    BankrBets public market;
    MockUSDC public usdc;
    MockRegistry public registry;
    MockV3Pool public pool;

    address public agentA = makeAddr("agentA");
    address public agentB = makeAddr("agentB");
    address public nonAgent = makeAddr("nonAgent");
    address public feeRecipient = makeAddr("feeRecipient");

    int24 constant INITIAL_TICK = 1000;
    uint32 constant TWAP_WINDOW = 30 minutes;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new MockRegistry();
        pool = new MockV3Pool();

        pool.setTick(INITIAL_TICK);
        // Set TWAP cumulatives so TWAP tick = INITIAL_TICK
        // TWAP = (cum1 - cum0) / window => cum1 - cum0 = INITIAL_TICK * window
        _setTwapTick(INITIAL_TICK);

        market = new BankrBets(
            address(usdc),
            address(registry),
            address(pool),
            feeRecipient,
            true // bnkrIsToken0
        );

        // Register agents
        registry.register(agentA, 1);
        registry.register(agentB, 2);

        // Mint USDC and approve
        usdc.mint(agentA, 1000e6);
        usdc.mint(agentB, 1000e6);

        vm.prank(agentA);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(agentB);
        usdc.approve(address(market), type(uint256).max);
    }

    /// @dev Helper to set mock TWAP tick
    function _setTwapTick(int24 tick) internal {
        int56 cum0 = 0;
        int56 cum1 = int56(tick) * int56(uint56(TWAP_WINDOW));
        pool.setTickCumulatives(cum0, cum1);
    }

    // ── Create Bet Tests ──────────────────────────────────────

    function test_createBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        assertEq(betId, 1);
        (
            address creator,,,
            uint256 amount,
            int24 strikeTick,
            uint256 expiry,
            BankrBets.Status status,
        ) = market.getBet(betId);

        assertEq(creator, agentA);
        assertEq(amount, 50e6);
        assertEq(strikeTick, INITIAL_TICK);
        assertEq(expiry, block.timestamp + 1 hours);
        assertEq(uint8(status), uint8(BankrBets.Status.OPEN));
        assertEq(usdc.balanceOf(address(market)), 50e6);
    }

    function test_createBet_revertIfNotRegistered() public {
        vm.prank(nonAgent);
        vm.expectRevert(BankrBets.NotRegisteredAgent.selector);
        market.createBet(BankrBets.Direction.LONG, 50e6);
    }

    function test_createBet_revertIfTooLow() public {
        vm.prank(agentA);
        vm.expectRevert(BankrBets.BetAmountTooLow.selector);
        market.createBet(BankrBets.Direction.LONG, 0.5e6);
    }

    function test_createBet_revertIfTooHigh() public {
        vm.prank(agentA);
        vm.expectRevert(BankrBets.BetAmountTooHigh.selector);
        market.createBet(BankrBets.Direction.LONG, 101e6);
    }

    // ── Take Bet Tests ────────────────────────────────────────

    function test_takeBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        (,address taker,,,,, BankrBets.Status status,) = market.getBet(betId);
        assertEq(taker, agentB);
        assertEq(uint8(status), uint8(BankrBets.Status.ACTIVE));
        assertEq(usdc.balanceOf(address(market)), 100e6);
    }

    function test_takeBet_revertIfOwnBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentA);
        vm.expectRevert(BankrBets.CannotTakeOwnBet.selector);
        market.takeBet(betId);
    }

    function test_takeBet_revertIfAlreadyTaken() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // Register a third agent
        address agentC = makeAddr("agentC");
        registry.register(agentC, 3);
        usdc.mint(agentC, 1000e6);
        vm.prank(agentC);
        usdc.approve(address(market), type(uint256).max);

        vm.prank(agentC);
        vm.expectRevert(BankrBets.BetNotOpen.selector);
        market.takeBet(betId);
    }

    // ── Settlement Tests ──────────────────────────────────────

    function test_settle_longWins() public {
        // Agent A goes LONG, TWAP tick goes up -> Agent A wins
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // TWAP tick goes UP (bnkrIsToken0 = true, so higher tick = BNKR up)
        _setTwapTick(INITIAL_TICK + 100);

        // Fast forward past expiry
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balBefore = usdc.balanceOf(agentA);
        market.settle(betId);

        // Winner gets pot minus 1% fee: 100e6 - 1e6 = 99e6
        assertEq(usdc.balanceOf(agentA) - balBefore, 99e6);
        assertEq(market.accumulatedFees(), 1e6);
    }

    function test_settle_shortWins() public {
        // Agent A goes SHORT, TWAP tick goes down -> Agent A wins
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.SHORT, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // TWAP tick goes DOWN
        _setTwapTick(INITIAL_TICK - 100);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balBefore = usdc.balanceOf(agentA);
        market.settle(betId);

        assertEq(usdc.balanceOf(agentA) - balBefore, 99e6);
    }

    function test_settle_takerWins() public {
        // Agent A goes LONG, TWAP tick goes DOWN -> Agent B (taker, SHORT) wins
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // TWAP tick goes DOWN
        _setTwapTick(INITIAL_TICK - 100);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balBefore = usdc.balanceOf(agentB);
        market.settle(betId);

        assertEq(usdc.balanceOf(agentB) - balBefore, 99e6);
    }

    function test_settle_draw() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // TWAP tick stays the same
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balABefore = usdc.balanceOf(agentA);
        uint256 balBBefore = usdc.balanceOf(agentB);
        market.settle(betId);

        // Draw: both get half of (pot - fee) = (100e6 - 1e6) / 2 = 49.5e6
        assertEq(usdc.balanceOf(agentA) - balABefore, 49500000);
        assertEq(usdc.balanceOf(agentB) - balBBefore, 49500000);
    }

    function test_settle_revertIfNotExpired() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        vm.expectRevert(BankrBets.BetNotExpired.selector);
        market.settle(betId);
    }

    function test_settle_revertIfNotActive() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(BankrBets.BetNotActive.selector);
        market.settle(betId);
    }

    // ── Cancel Tests ──────────────────────────────────────────

    function test_cancelBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        uint256 balBefore = usdc.balanceOf(agentA);
        vm.prank(agentA);
        market.cancelBet(betId);

        assertEq(usdc.balanceOf(agentA) - balBefore, 50e6);
        (,,,,,, BankrBets.Status status,) = market.getBet(betId);
        assertEq(uint8(status), uint8(BankrBets.Status.CANCELLED));
    }

    function test_cancelBet_revertIfNotCreator() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        vm.expectRevert(BankrBets.OnlyCreatorCanCancel.selector);
        market.cancelBet(betId);
    }

    function test_cancelBet_revertIfActive() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        vm.prank(agentA);
        vm.expectRevert(BankrBets.BetNotOpen.selector);
        market.cancelBet(betId);
    }

    // ── Fee Withdrawal Tests ──────────────────────────────────

    function test_withdrawFees() public {
        // Create and settle a bet to accumulate fees
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);
        vm.prank(agentB);
        market.takeBet(betId);
        _setTwapTick(INITIAL_TICK + 100);
        vm.warp(block.timestamp + 1 hours + 1);
        market.settle(betId);

        assertEq(market.accumulatedFees(), 1e6);

        market.withdrawFees();
        assertEq(usdc.balanceOf(feeRecipient), 1e6);
        assertEq(market.accumulatedFees(), 0);
    }

    function test_withdrawFees_revertIfNone() public {
        vm.expectRevert(BankrBets.NoFeesToWithdraw.selector);
        market.withdrawFees();
    }

    // ── Token Ordering Tests (bnkrIsToken0 = false) ───────────

    function test_settle_invertedTokenOrder() public {
        // Deploy with bnkrIsToken0 = false
        BankrBets invertedMarket = new BankrBets(
            address(usdc),
            address(registry),
            address(pool),
            feeRecipient,
            false // bnkrIsToken0 = false
        );

        vm.prank(agentA);
        usdc.approve(address(invertedMarket), type(uint256).max);
        vm.prank(agentB);
        usdc.approve(address(invertedMarket), type(uint256).max);

        // Agent A goes LONG
        vm.prank(agentA);
        uint256 betId = invertedMarket.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        invertedMarket.takeBet(betId);

        // When bnkrIsToken0 = false, LOWER tick = BNKR price UP
        // So decreasing tick means LONG wins
        _setTwapTick(INITIAL_TICK - 100);
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balBefore = usdc.balanceOf(agentA);
        invertedMarket.settle(betId);
        assertEq(usdc.balanceOf(agentA) - balBefore, 99e6);
    }

    // ── Edge Cases ────────────────────────────────────────────

    function test_maxBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 100e6);

        (,,, uint256 amount,,,,) = market.getBet(betId);
        assertEq(amount, 100e6);
    }

    function test_minBet() public {
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.SHORT, 1e6);

        (,,, uint256 amount,,,,) = market.getBet(betId);
        assertEq(amount, 1e6);
    }

    function test_multipleBets() public {
        vm.startPrank(agentA);
        uint256 bet1 = market.createBet(BankrBets.Direction.LONG, 50e6);
        uint256 bet2 = market.createBet(BankrBets.Direction.SHORT, 25e6);
        vm.stopPrank();

        assertEq(bet1, 1);
        assertEq(bet2, 2);
        assertEq(market.nextBetId(), 3);
    }

    function test_getCurrentTick() public view {
        int24 tick = market.getCurrentTick();
        assertEq(tick, INITIAL_TICK);
    }

    function test_getSettlementTick() public {
        _setTwapTick(INITIAL_TICK + 50);
        int24 twapTick = market.getSettlementTick();
        assertEq(twapTick, INITIAL_TICK + 50);
    }

    // ── TWAP-specific Tests ────────────────────────────────────

    function test_settle_usesTwapNotSpot() public {
        // Verify that settlement uses TWAP, not spot price.
        // Set spot tick high (simulating flash loan) but TWAP tick low.
        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // Spot tick goes way UP (flash loan manipulation)
        pool.setTick(INITIAL_TICK + 10000);
        // But TWAP tick goes DOWN (real market movement)
        _setTwapTick(INITIAL_TICK - 100);

        vm.warp(block.timestamp + 1 hours + 1);

        // LONG should LOSE because TWAP went down, despite spot going up
        uint256 balBefore = usdc.balanceOf(agentB);
        market.settle(betId);

        // Agent B (SHORT taker) wins
        assertEq(usdc.balanceOf(agentB) - balBefore, 99e6);
    }

    function test_settle_negativeTwapTick() public {
        // Test with negative ticks
        pool.setTick(-500);
        _setTwapTick(-500);

        vm.prank(agentA);
        uint256 betId = market.createBet(BankrBets.Direction.LONG, 50e6);

        vm.prank(agentB);
        market.takeBet(betId);

        // TWAP tick goes further negative (price down)
        _setTwapTick(-600);

        vm.warp(block.timestamp + 1 hours + 1);

        // SHORT (taker) wins
        uint256 balBefore = usdc.balanceOf(agentB);
        market.settle(betId);
        assertEq(usdc.balanceOf(agentB) - balBefore, 99e6);
    }
}
