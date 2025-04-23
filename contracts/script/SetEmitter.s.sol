// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/PeridotHub.sol"; // Import the Hub interface/contract

contract SetSpokeEmitter is Script {
    // --- CONFIGURATION ---
    // !!! Replace with your deployed addresses !!!
    address payable constant HUB_ADDRESS =
        payable(0x8F9d1f504B13726d0977216CF81fB1e7d81a497C); // Changed to address payable
    address constant SPOKE_ADDRESS = 0x35280b6EA83Fd265D316037432e62870409eaC5b; // Replace!
    uint16 constant SPOKE_CHAIN_ID = 10004; // Example: Replace with the actual spoke chain ID

    function run() public {
        console.log("Setting Spoke as Trusted Emitter on Hub...");
        console.log("  Hub Address:", HUB_ADDRESS);
        console.log("  Spoke Address:", SPOKE_ADDRESS);
        console.log("  Spoke Chain ID:", SPOKE_CHAIN_ID);

        // Convert the spoke address to bytes32 format
        bytes32 spokeEmitterAddressBytes32 = bytes32(
            uint256(uint160(SPOKE_ADDRESS))
        );
        // Use vm.toString() to log the bytes32 value
        console.log(
            "  Spoke Address (bytes32):",
            vm.toString(spokeEmitterAddressBytes32)
        );

        vm.startBroadcast();

        PeridotHub hub = PeridotHub(HUB_ADDRESS);

        // Call setTrustedEmitter on the Hub
        hub.setTrustedEmitter(
            SPOKE_CHAIN_ID,
            spokeEmitterAddressBytes32, // Pass the converted bytes32 address
            true // Set status to trusted
        );

        vm.stopBroadcast();

        console.log("==== Operation Complete ====");
        console.log("Successfully set Spoke emitter on Hub.");

        // Optional: Verify the setting
        bool isTrusted = hub.trustedEmitters(
            SPOKE_CHAIN_ID,
            spokeEmitterAddressBytes32
        );
        console.log("Verification - Is emitter trusted:", isTrusted);
        require(isTrusted, "Verification failed: Emitter not set as trusted.");
    }
}
