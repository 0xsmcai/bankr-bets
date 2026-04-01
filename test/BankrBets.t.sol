// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BankrBets} from "../src/BankrBets.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ── Mocks ─────────────────────────────────────────────────────────

contract MockUSDC {
    string public name = "Mock USDC";
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
        require(allowance[from][msg.sender] >= amount, "not approved");
        require(balanceOf[from] >= amount, "insufficient");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockRegistry {
    mapping(address => uint256) public balanceOf;

    function registerAgent(address agent) external {
        balanceOf[agent] = 1;
    }
}

contract MockV3Pool {
    int24 public currentTick;

    constructor(int24 _tick) {
        currentTick = _tick;
    }

    function setTick(int24 _tick) external {
        currentTick = _tick;
    }

    function slot0() external view returns (
        uint160, int24, uint16, uint16, uint16, uint8, bool
    ) {
        return (0, currentTick, 0, 1000, 1000, 0, true);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            // tickCumulative = tick * timestamp
            // For two timestamps t0 and t1: TWAP = (cum[t1] - cum[t0]) / (t1 - t0) = currentTick
            uint256 timestamp = block.timestamp - secondsAgos[i];
            tickCumulatives[i] = int56(currentTick) * int56(int256(timestamp));
        }
    }
}

contract BrokenPool {
    function observe(uint32[] calldata) external pure returns (int56[] memory, uint160[] memory) {
        revert("oracle broken");
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (0, 0, 0, 0, 0, 0, true);
    }
}

// ── Test Suite ────────────────────────────────────────────────────

contract BankrBetsTest is Test {
    BankrBets public market;
    MockUSDC public usdc;
    MockRegistry public registry;
    MockV3Pool public pool;

    address admin = makeAddr("admin");
    address keeper = makeAddr("keeper");
    address treasury = makeAddr("treasury");
    address insurance = makeAddr("insurance");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    address constant DRB = address(0xD4B);

    function setUp() public {
        // Warp to a reasonable timestamp so TWAP observe() doesn't underflow
        vm.warp(1_700_000_000); // ~2023

        usdc = new MockUSDC();
        registry = new MockRegistry();
        pool = new MockV3Pool(100); // starting tick

        market = new BankrBets(
            address(usdc),
            address(registry),
            keeper,
            treasury,
            insurance,
            admin
        );

        // Add DRB token
        vm.prank(admin);
        market.addToken(DRB, address(pool), true);

        // Fund users
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(carol, 100_000e6);

        // Register alice as agent
        registry.registerAgent(alice);
    }

    // ── Helpers ───────────────────────────────────────────────────

    function _createMarket() internal returns (uint256) {
        vm.prank(keeper);
        return market.createMarket(DRB, BankrBets.Duration.ONE_HOUR);
    }

    function _betUp(address user, uint256 amount) internal {
        _bet(user, 1, amount, true);
    }

    function _betDown(address user, uint256 amount) internal {
        _bet(user, 1, amount, false);
    }

    function _bet(address user, uint256 marketId, uint256 amount, bool isUp) internal {
        vm.startPrank(user);
        usdc.approve(address(market), amount);
        market.bet(marketId, isUp, amount);
        vm.stopPrank();
    }

    function _resolveUp(uint256 marketId) internal {
        pool.setTick(200); // tick went up from 100
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        market.resolve(marketId, 200);
    }

    function _resolveDown(uint256 marketId) internal {
        pool.setTick(-50); // tick went down from 100
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        market.resolve(marketId, -50);
    }

    // ── Market Creation ───────────────────────────────────────────

    function test_createMarket() public {
        uint256 id = _createMarket();
        assertEq(id, 1);
        BankrBets.Market memory m = market.getMarket(1);
        assertEq(m.token, DRB);
        assertEq(m.openingTick, 100);
        assertFalse(m.resolved);
    }

    function test_createMarket_revertIfNotKeeper() public {
        vm.prank(alice);
        vm.expectRevert(BankrBets.NotKeeper.selector);
        market.createMarket(DRB, BankrBets.Duration.ONE_HOUR);
    }

    function test_createMarket_revertIfTokenNotActive() public {
        vm.prank(keeper);
        vm.expectRevert(BankrBets.TokenNotActive.selector);
        market.createMarket(address(0x123), BankrBets.Duration.ONE_HOUR);
    }

    function test_createMarket_revertIfPaused() public {
        vm.prank(admin);
        market.pause();
        vm.prank(keeper);
        vm.expectRevert();
        market.createMarket(DRB, BankrBets.Duration.ONE_HOUR);
    }

    // ── Betting ───────────────────────────────────────────────────

    function test_bet_up() public {
        _createMarket();
        _betUp(alice, 500e6);

        BankrBets.UserPosition memory pos = market.getPosition(1, alice);
        assertEq(pos.amount, 500e6);
        assertEq(pos.side, 1); // UP
        assertTrue(pos.isAgent); // alice is registered
    }

    function test_bet_down() public {
        _createMarket();
        _betDown(bob, 300e6);

        BankrBets.UserPosition memory pos = market.getPosition(1, bob);
        assertEq(pos.amount, 300e6);
        assertEq(pos.side, 2); // DOWN
        assertFalse(pos.isAgent); // bob not registered
    }

    function test_bet_agentTagging() public {
        _createMarket();
        _betUp(alice, 100e6); // registered agent
        _betDown(bob, 100e6); // not registered

        assertTrue(market.getPosition(1, alice).isAgent);
        assertFalse(market.getPosition(1, bob).isAgent);
    }

    function test_bet_multipleBetsSameSide() public {
        _createMarket();
        _betUp(alice, 200e6);
        _betUp(alice, 300e6);

        BankrBets.UserPosition memory pos = market.getPosition(1, alice);
        assertEq(pos.amount, 500e6);
    }

    function test_bet_revertIfBettingClosed() public {
        _createMarket();
        // Warp past betting deadline (closeTime - 15min for 1h market)
        vm.warp(block.timestamp + 46 minutes); // past 45min deadline
        vm.startPrank(alice);
        usdc.approve(address(market), 100e6);
        vm.expectRevert(BankrBets.BettingClosed.selector);
        market.bet(1, true, 100e6);
        vm.stopPrank();
    }

    function test_bet_revertIfTooSmall() public {
        _createMarket();
        vm.startPrank(alice);
        usdc.approve(address(market), 0.5e6);
        vm.expectRevert(BankrBets.BetTooSmall.selector);
        market.bet(1, true, 0.5e6);
        vm.stopPrank();
    }

    function test_bet_revertIfTooLarge() public {
        _createMarket();
        vm.startPrank(alice);
        usdc.approve(address(market), 2_000e6);
        vm.expectRevert(BankrBets.BetTooLarge.selector);
        market.bet(1, true, 2_000e6);
        vm.stopPrank();
    }

    function test_bet_revertIfMarketCapExceeded() public {
        _createMarket();
        _betUp(alice, 1_000e6);
        _betDown(bob, 1_000e6);
        for (uint256 i = 0; i < 8; i++) {
            address bettor = makeAddr(string(abi.encodePacked("bettor", i)));
            usdc.mint(bettor, 1_000e6);
            vm.startPrank(bettor);
            usdc.approve(address(market), 1_000e6);
            market.bet(1, i % 2 == 0, 1_000e6);
            vm.stopPrank();
        }
        address lastBettor = makeAddr("lastBettor");
        usdc.mint(lastBettor, 100e6);
        vm.startPrank(lastBettor);
        usdc.approve(address(market), 100e6);
        vm.expectRevert(BankrBets.MarketCapExceeded.selector);
        market.bet(1, true, 100e6);
        vm.stopPrank();
    }

    function test_bet_revertIfPaused() public {
        _createMarket();
        vm.prank(admin);
        market.pause();
        vm.startPrank(alice);
        usdc.approve(address(market), 100e6);
        vm.expectRevert();
        market.bet(1, true, 100e6);
        vm.stopPrank();
    }

    // ── Resolution ────────────────────────────────────────────────

    function test_resolve_upWins() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        BankrBets.Market memory m = market.getMarket(1);
        assertTrue(m.resolved);
        assertEq(uint8(m.outcome), uint8(BankrBets.Outcome.UP));
    }

    function test_resolve_downWins() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveDown(1);

        BankrBets.Market memory m = market.getMarket(1);
        assertEq(uint8(m.outcome), uint8(BankrBets.Outcome.DOWN));
    }

    function test_resolve_flatPrice_voids() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        // Tick stays at 100 (same as opening)
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        market.resolve(1, 100);

        BankrBets.Market memory m = market.getMarket(1);
        assertEq(uint8(m.outcome), uint8(BankrBets.Outcome.VOIDED));
    }

    function test_resolve_oracleDivergence_reverts() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        pool.setTick(200);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        // offChainTick = 5000, TWAP = 200, divergence = 4800 > 2000
        vm.expectRevert(BankrBets.OracleDivergence.selector);
        market.resolve(1, 5000);
    }

    function test_resolve_minimumNotMet_voids() public {
        _createMarket();
        _betUp(alice, 10e6); // only $10 UP, $0 DOWN

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        market.resolve(1, 200);

        BankrBets.Market memory m = market.getMarket(1);
        assertEq(uint8(m.outcome), uint8(BankrBets.Outcome.VOIDED));
    }

    function test_resolve_revertIfNotKeeper() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert(BankrBets.NotKeeper.selector);
        market.resolve(1, 200);
    }

    function test_resolve_revertIfTooEarly() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        // Don't warp — still before closeTime
        vm.prank(keeper);
        vm.expectRevert(BankrBets.MarketNotClosed.selector);
        market.resolve(1, 200);
    }

    function test_resolve_revertIfAlreadyResolved() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        vm.prank(keeper);
        vm.expectRevert(BankrBets.MarketAlreadyResolved.selector);
        market.resolve(1, 200);
    }

    // ── TWAP Fallback ─────────────────────────────────────────────

    function test_resolveByTwap_afterGracePeriod() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        pool.setTick(200);
        vm.warp(block.timestamp + 1 hours + 2 hours + 1); // past grace

        market.resolveByTwap(1); // permissionless

        BankrBets.Market memory m = market.getMarket(1);
        assertTrue(m.resolved);
        assertEq(uint8(m.outcome), uint8(BankrBets.Outcome.UP));
    }

    function test_resolveByTwap_revertIfGraceNotElapsed() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        vm.warp(block.timestamp + 1 hours + 1); // past close but not past grace
        vm.expectRevert(BankrBets.GracePeriodNotElapsed.selector);
        market.resolveByTwap(1);
    }

    // ── Claiming ──────────────────────────────────────────────────

    function test_claim_winnerGetsPayout() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = market.claim(1);
        uint256 balAfter = usdc.balanceOf(alice);

        // Payout = 1000 * 0.97 * (500/500) = 970 USDC
        assertEq(payout, 970e6);
        assertEq(balAfter - balBefore, 970e6);
    }

    function test_claim_proportionalPayout() public {
        _createMarket();
        _betUp(alice, 200e6);  // 200 UP
        _betUp(carol, 300e6);  // 300 UP (total UP = 500)
        _betDown(bob, 500e6);  // 500 DOWN

        _resolveUp(1);

        // Total pool = 1000, distributable = 970
        // Alice: 970 * 200 / 500 = 388
        vm.prank(alice);
        uint256 alicePayout = market.claim(1);
        assertEq(alicePayout, 388e6);

        // Carol: 970 * 300 / 500 = 582
        vm.prank(carol);
        uint256 carolPayout = market.claim(1);
        assertEq(carolPayout, 582e6);

        // Total distributed: 388 + 582 = 970. Fee = 30. Sum = 1000.
    }

    function test_claim_voidedMarket_refunds() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);

        // Flat price → void
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(keeper);
        market.resolve(1, 100);

        // Both sides get full refund
        vm.prank(alice);
        assertEq(market.claim(1), 500e6);

        vm.prank(bob);
        assertEq(market.claim(1), 500e6);
    }

    function test_claim_revertIfAlreadyClaimed() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        vm.prank(alice);
        market.claim(1);

        vm.prank(alice);
        vm.expectRevert(BankrBets.AlreadyClaimed.selector);
        market.claim(1);
    }

    function test_claim_revertIfNotWinner() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        vm.prank(bob); // bob bet DOWN, UP won
        vm.expectRevert(BankrBets.NotWinner.selector);
        market.claim(1);
    }

    function test_claim_revertIfNotResolved() public {
        _createMarket();
        _betUp(alice, 500e6);

        vm.prank(alice);
        vm.expectRevert(BankrBets.MarketNotResolved.selector);
        market.claim(1);
    }

    function test_claim_revertIfNoBet() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        vm.prank(carol); // carol didn't bet
        vm.expectRevert(BankrBets.NoBet.selector);
        market.claim(1);
    }

    // ── Emergency Withdraw ────────────────────────────────────────

    function test_emergencyWithdraw_whenPaused() public {
        _createMarket();
        _betUp(alice, 500e6);

        vm.prank(admin);
        market.pause();

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        market.emergencyWithdraw(1);
        uint256 balAfter = usdc.balanceOf(alice);

        assertEq(balAfter - balBefore, 500e6); // full refund
    }

    function test_emergencyWithdraw_afterGracePeriod() public {
        _createMarket();
        _betUp(alice, 500e6);

        vm.warp(block.timestamp + 1 hours + 2 hours + 1);

        vm.prank(alice);
        market.emergencyWithdraw(1);
    }

    function test_emergencyWithdraw_revertIfResolved() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        vm.prank(alice);
        vm.expectRevert(BankrBets.MarketAlreadyResolved.selector);
        market.emergencyWithdraw(1);
    }

    function test_emergencyWithdraw_revertIfNotEmergency() public {
        _createMarket();
        _betUp(alice, 500e6);

        vm.prank(alice);
        vm.expectRevert(BankrBets.NotVoidedOrUnresolved.selector);
        market.emergencyWithdraw(1);
    }

    // ── Admin ─────────────────────────────────────────────────────

    function test_setKeeper() public {
        vm.prank(admin);
        market.setKeeper(alice);
        assertEq(market.keeper(), alice);
    }

    function test_addRemoveToken() public {
        address newToken = address(0xBEEF);
        vm.prank(admin);
        market.addToken(newToken, address(pool), false);

        (,, bool active) = market.tokens(newToken);
        assertTrue(active);

        vm.prank(admin);
        market.removeToken(newToken);
        (,, active) = market.tokens(newToken);
        assertFalse(active);
    }

    function test_ownable2Step() public {
        vm.prank(admin);
        market.transferOwnership(alice);

        // alice hasn't accepted yet
        assertEq(market.owner(), admin);

        vm.prank(alice);
        market.acceptOwnership();
        assertEq(market.owner(), alice);
    }

    // ── Fee Distribution ──────────────────────────────────────────

    function test_distributeFees() public {
        _createMarket();
        _betUp(alice, 500e6);
        _betDown(bob, 500e6);
        _resolveUp(1);

        // Claim first so fees accumulate
        vm.prank(alice);
        market.claim(1);

        // Distribute: 3% of 1000 = 30. Treasury: 20, Insurance: 10
        market.distributeFees(1);

        assertEq(usdc.balanceOf(treasury), 20e6);
        assertEq(usdc.balanceOf(insurance), 10e6);
    }

    // ── Oracle Error ──────────────────────────────────────────────

    function test_createMarket_revertIfOracleError() public {
        BrokenPool broken = new BrokenPool();
        vm.prank(admin);
        market.addToken(address(0xBAD), address(broken), true);

        vm.prank(keeper);
        vm.expectRevert(BankrBets.OracleError.selector);
        market.createMarket(address(0xBAD), BankrBets.Duration.ONE_HOUR);
    }

    // ── View Functions ────────────────────────────────────────────

    function test_activeMarketIds() public {
        _createMarket(); // id 1
        vm.prank(keeper);
        market.createMarket(DRB, BankrBets.Duration.FOUR_HOUR); // id 2

        uint256[] memory ids = market.activeMarketIds();
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }
}
