// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IWormhole} from "../lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TransferToken is Script {
    // --- CONFIGURATION (Source Chain - Arbitrum Sepolia) ---
    address constant WORMHOLE = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35; // Wormhole core on Arbitrum Sepolia
    address constant TOKEN_BRIDGE = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e; // Wormhole TokenBridge on Arbitrum Sepolia
    address constant TOKEN_TO_TRANSFER =
        0xDEe566b3Fe99F8d9934BAAEEdDA298D5B76B8868; // Address of the ORIGINAL ERC20 on Arbitrum

    // --- CONFIGURATION (Destination Chain - Base Sepolia) ---
    uint16 constant DESTINATION_CHAIN_ID = 10004; // Wormhole Chain ID for Base Sepolia (Verify this ID from Wormhole docs)
    address constant RECIPIENT_ADDRESS =
        0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // Address on Base Sepolia to receive wrapped tokens (e.g., your address)

    // --- TRANSFER DETAILS ---
    uint256 constant TRANSFER_AMOUNT_UNSCALED = 100; // The amount of tokens to send (e.g., 100)
    uint8 constant TOKEN_DECIMALS = 18; // Decimals of your TOKEN_TO_TRANSFER
    uint32 constant NONCE = 42069421; // Needs to be different from the attest nonce!
    uint256 constant ARBITER_FEE = 0; // Usually 0 unless using a specific relayer service

    function run() external {
        console.log(" Initiating Token Transfer via Token Bridge...");
        console.log("  Source Chain: Arbitrum Sepolia");
        console.log("  Destination Chain ID:", DESTINATION_CHAIN_ID);
        console.log("  Token Address:", TOKEN_TO_TRANSFER);
        console.log("  Recipient Address:", RECIPIENT_ADDRESS);
        console.log("  Amount (Unscaled):", TRANSFER_AMOUNT_UNSCALED);

        uint256 transferAmountScaled = TRANSFER_AMOUNT_UNSCALED *
            (10 ** TOKEN_DECIMALS);
        console.log("  Amount (Scaled):", transferAmountScaled);

        // Convert recipient address to bytes32 format
        bytes32 recipientBytes32 = bytes32(uint256(uint160(RECIPIENT_ADDRESS)));
        console.log("  Recipient (bytes32):");
        console.logBytes32(recipientBytes32);

        vm.startBroadcast();

        // 1. Approve the Token Bridge to spend the tokens
        console.log("  Approving Token Bridge to spend tokens...");
        IERC20(TOKEN_TO_TRANSFER).approve(TOKEN_BRIDGE, transferAmountScaled);
        console.log("  Approval successful.");

        // 2. Figure out the Wormhole message fee
        // Although transferTokens has an arbiterFee param, the tx often needs the base messageFee value
        uint256 msgFee = IWormhole(WORMHOLE).messageFee();
        console.log("  Wormhole message fee:", msgFee);

        // 3. Call transferTokens
        console.log("  Calling transferTokens...");
        uint64 sequence = ITokenBridge(TOKEN_BRIDGE).transferTokens{
            value: msgFee
        }(
            TOKEN_TO_TRANSFER,
            transferAmountScaled,
            DESTINATION_CHAIN_ID,
            recipientBytes32,
            ARBITER_FEE,
            NONCE
        );
        console.log(" transferTokens sequence:", sequence);

        vm.stopBroadcast();

        // Emitter info for fetching the TRANSFER VAA:
        bytes32 emitter = bytes32(uint256(uint160(TOKEN_BRIDGE)));
        console.log("  Emitter (bytes32):");
        console.logBytes32(emitter);
        console.log("  Sequence:", sequence);
        console.log(
            "  Now fetch this TRANSFER VAA using the emitter and sequence."
        );
        console.log(
            "  Next step: Use the fetched VAA to call 'completeTransfer' on Base Sepolia's Token Bridge."
        );
    }
}
