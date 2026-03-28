// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/BankrBets.sol";

contract DeployBankrBets is Script {
    // Base mainnet addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    function run() external {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address bnkrPool = vm.envAddress("BNKR_POOL");
        bool bnkrIsToken0 = vm.envBool("BNKR_IS_TOKEN0");

        require(bnkrPool != address(0), "BNKR_POOL env var must be set to the V3 pool address");

        vm.startBroadcast();

        BankrBets market = new BankrBets(
            USDC,
            IDENTITY_REGISTRY,
            bnkrPool,
            feeRecipient,
            bnkrIsToken0
        );

        vm.stopBroadcast();

        console.log("BankrBets deployed at:", address(market));
        console.log("Fee recipient:", feeRecipient);
        console.log("BNKR is token0:", bnkrIsToken0);
    }
}
