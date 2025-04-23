// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {BytesParsing} from "../lib/wormhole-solidity-sdk/src/libraries/BytesParsing.sol";
import "../lib/wormhole-ntt/src/interfaces/INttManager.sol";

contract TransferNttToken is Script {
    // --- Deployment Config (from deployment.json) ---
    address constant ARB_SEPOLIA_NTT_MANAGER =
        0x10b644913592549aAf55ED9573E8455e70692EeB;
    address constant ARB_SEPOLIA_TOKEN =
        0x3ed59D5D0a2236cDAd22aDFFC5414df74Ccb3040;
    uint16 constant BASE_SEPOLIA_CHAIN_ID = 10004; // Wormhole Chain ID for Base Sepolia

    // --- Transfer Details (CONFIGURE THESE) ---
    // Recipient address on Base Sepolia (must be a 20-byte address)
    address constant RECIPIENT_ADDRESS_BASE =
        0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9;
    // Amount to transfer (in ATOMIC units - e.g., if 18 decimals, 1 * 10**18 for 1 token)
    uint256 constant TRANSFER_AMOUNT_ATOMIC = 1 * 10 ** 18; // Example: 1 token with 18 decimals

    // --- Interfaces ---
    INttManager nttManager = INttManager(ARB_SEPOLIA_NTT_MANAGER);
    IERC20 token = IERC20(ARB_SEPOLIA_TOKEN);

    function run() external {
        // Input Validation
        require(
            RECIPIENT_ADDRESS_BASE != address(0),
            "Recipient address cannot be zero"
        );
        require(
            TRANSFER_AMOUNT_ATOMIC > 0,
            "Transfer amount must be greater than zero"
        );

        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address sender = vm.addr(deployerPrivateKey);

        // Check token balance
        uint256 balance = token.balanceOf(sender);
        console.log("Sender Address:", sender);
        console.log("Sender Token Balance (atomic):", balance);
        require(
            balance >= TRANSFER_AMOUNT_ATOMIC,
            "Insufficient token balance"
        );

        // Format recipient address to bytes32 (Wormhole format)
        bytes32 recipientBytes32 = bytes32(
            uint256(uint160(RECIPIENT_ADDRESS_BASE))
        );
        console.log(
            "Recipient Address (Base Sepolia):",
            RECIPIENT_ADDRESS_BASE
        );
        console.log("Recipient Address (bytes32):");
        console.logBytes32(recipientBytes32);

        // Get estimated delivery fee
        (, uint256 totalFee) = nttManager.quoteDeliveryPrice(
            BASE_SEPOLIA_CHAIN_ID,
            hex"00"
        );
        console.log("Estimated Delivery Fee (Wei):", totalFee);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // 1. Approve the NTT Manager to spend the tokens
        console.log("Approving NTT Manager to spend tokens...");
        token.approve(ARB_SEPOLIA_NTT_MANAGER, TRANSFER_AMOUNT_ATOMIC);
        console.log("Approval successful.");

        // 2. Initiate the transfer
        console.log("Initiating NTT transfer...");
        uint64 sequence = nttManager.transfer{value: totalFee}(
            TRANSFER_AMOUNT_ATOMIC,
            BASE_SEPOLIA_CHAIN_ID,
            recipientBytes32
        );
        console.log("Transfer initiated. Sequence:", sequence);

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("Script finished successfully.");
    }
}
