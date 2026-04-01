// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BankrBets} from "../src/BankrBets.sol";

/// @notice Mock USDC for testnet
contract MockUSDC {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount);
        require(balanceOf[from] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Mock Identity Registry
contract MockRegistry {
    mapping(address => uint256) public _balances;

    function register(address agent) external {
        _balances[agent] = 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}

/// @notice Mock V3 Pool with configurable TWAP
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
        return (0, currentTick, 0, 10000, 10000, 0, true);
    }

    function observe(uint32[] calldata secondsAgos)
        external view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            uint256 ts = block.timestamp - secondsAgos[i];
            tickCumulatives[i] = int56(currentTick) * int56(int256(ts));
        }
    }
}

contract DeployTestnet is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy mocks
        MockUSDC usdc = new MockUSDC();
        MockRegistry registry = new MockRegistry();
        MockV3Pool drbPool = new MockV3Pool(100);
        MockV3Pool bnkrPool = new MockV3Pool(200);

        // Deploy BankrBets
        BankrBets market = new BankrBets(
            address(usdc),
            address(registry),
            msg.sender,     // keeper = deployer
            msg.sender,     // treasury = deployer
            msg.sender,     // insurance = deployer
            msg.sender      // admin = deployer
        );

        // Add tokens
        market.addToken(address(0xD4B), address(drbPool), true);   // DRB mock
        market.addToken(address(0xB14C), address(bnkrPool), true); // BNKR mock

        // Mint test USDC and register deployer as agent
        usdc.mint(msg.sender, 100_000e6);
        registry.register(msg.sender);

        vm.stopBroadcast();

        console.log("=== BANKR BETS v1 TESTNET ===");
        console.log("BankrBets:", address(market));
        console.log("MockUSDC:", address(usdc));
        console.log("MockRegistry:", address(registry));
        console.log("DRB Pool:", address(drbPool));
        console.log("BNKR Pool:", address(bnkrPool));
        console.log("Deployer:", msg.sender);
        console.log("Deployer USDC: 100,000");
        console.log("Deployer is agent ID 1");
    }
}
