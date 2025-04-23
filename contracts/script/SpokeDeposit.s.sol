// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/PeridotSpoke.sol"; // Import the Spoke contract
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol"; // For quoting fee

contract DepositOnSpoke is Script {
    // --- CONFIGURATION (Source Chain - Base Sepolia) ---
    address constant SPOKE_CONTRACT_ADDRESS =
        0xBFCB07d4279cAb8Bd81bdDCD49aE005F8514AceC; // Replace with your deployed PeridotSpoke address
    address constant TOKEN_TO_DEPOSIT =
        0x266e5B7fb5D918E5A3b2aEde73c2C694cF58E537; // The original ERC20 token on Base Sepolia
    address constant RELAYER_ADDRESS =
        0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE; // Replace with Wormhole Relayer address on Base Sepolia

    // --- CONFIGURATION (Needed for Fee Quote - from Spoke constructor) ---
    uint16 constant HUB_CHAIN_ID = 10003; // Example: Wormhole Chain ID for Arbitrum Sepolia
    address constant HUB_ADDRESS = 0x1E6869b8575Eee383112Ac5C830dF7b0FAE43Eb0; // Example: Your Hub address on Arbitrum Sepolia

    // --- DEPOSIT DETAILS ---
    uint256 constant DEPOSIT_AMOUNT = 1e18; // Deposit 1 token (assuming 18 decimals)
    uint256 constant GAS_LIMIT_FOR_HUB = 1000000; // Match the GAS_LIMIT in PeridotSpoke

    function run() external {
        require(
            SPOKE_CONTRACT_ADDRESS != address(0),
            "SPOKE_CONTRACT_ADDRESS not set"
        );
        require(TOKEN_TO_DEPOSIT != address(0), "TOKEN_TO_DEPOSIT not set");
        require(RELAYER_ADDRESS != address(0), "RELAYER_ADDRESS not set");
        require(HUB_ADDRESS != address(0), "HUB_ADDRESS not set");

        console.log("Depositing token via PeridotSpoke...");
        console.log("  Spoke Contract:", SPOKE_CONTRACT_ADDRESS);
        console.log("  Token:", TOKEN_TO_DEPOSIT);
        console.log("  Amount:", DEPOSIT_AMOUNT);

        // Get the relayer fee quote
        IWormholeRelayerSend relayer = IWormholeRelayerSend(RELAYER_ADDRESS);
        (uint256 deliveryCost, ) = relayer.quoteEVMDeliveryPrice(
            HUB_CHAIN_ID,
            0, // receiverValue (not sending extra native)
            GAS_LIMIT_FOR_HUB
        );
        console.log("  Calculated Relayer Delivery Cost:", deliveryCost);
        require(
            address(this).balance >= deliveryCost,
            "Script wallet does not have enough ETH to cover delivery cost"
        );

        vm.startBroadcast();

        // 1. Approve the Spoke Contract to spend the user's (script runner's) tokens
        console.log("  Approving Spoke contract to spend tokens...");
        IERC20(TOKEN_TO_DEPOSIT).approve(
            SPOKE_CONTRACT_ADDRESS,
            DEPOSIT_AMOUNT
        );
        console.log("  Approval successful.");

        // 2. Call the deposit function on the Spoke contract, sending the required fee
        PeridotSpoke spoke = PeridotSpoke(SPOKE_CONTRACT_ADDRESS);
        console.log("  Calling spoke.deposit{value: deliveryCost}()...");
        spoke.deposit{value: deliveryCost}(TOKEN_TO_DEPOSIT, DEPOSIT_AMOUNT);

        vm.stopBroadcast();

        console.log("Deposit transaction sent successfully!");
        console.log("   -> Spoke should have transferred tokens from you.");
        console.log(
            "   -> Spoke should have called TokenBridge.transferTokens."
        );
        console.log("   -> Spoke should have called Relayer.sendPayloadToEvm.");
        console.log(
            "   -> Wait for the Wormhole message to be relayed and processed by the Hub on Base Sepolia."
        );
    }
}
