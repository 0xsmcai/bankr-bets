// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/BankrBets.sol";

contract DeployBankrBets is Script {
    // Base mainnet addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    // BNKR V3 pool address — must be verified before mainnet deploy
    address constant BNKR_POOL = address(0); // TODO: set actual V3 pool address

    function run() external {
        address deployer = msg.sender;
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        bool bnkrIsToken0 = vm.envBool("BNKR_IS_TOKEN0");

        vm.startBroadcast();

        BankrBets market = new BankrBets(
            USDC,
            IDENTITY_REGISTRY,
            BNKR_POOL,
            feeRecipient,
            bnkrIsToken0
        );

        vm.stopBroadcast();

        console.log("BankrBets deployed at:", address(market));
        console.log("Fee recipient:", feeRecipient);
        console.log("BNKR is token0:", bnkrIsToken0);
    }
}
