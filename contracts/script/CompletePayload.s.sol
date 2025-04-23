// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol"; // For checking balance

contract CompletePayload is Script {
    // --- CONFIGURATION (Destination Chain - Base Sepolia) ---
    address constant TOKEN_BRIDGE = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e; // Token Bridge on Base Sepolia
    address constant RECIPIENT_ADDRESS =
        0x56f8868EFAe647c3DDc64C1be9C099FC11C6FB93; // The recipient address specified in the TransferTokens script
    address constant WRAPPED_TOKEN_ADDRESS =
        0xDEe566b3Fe99F8d9934BAAEEdDA298D5B76B8868; // The address of the wrapped token deployed by createWrapped

    // --- VAA ---

    // Get hex-encoded VAA (f.e.: AQAAAAABAGKNsn30EWdX3FH2S/4OGnhKTKVSq62fXzsic7bRE5UVeVKbzbaGjRb6ULF4wAQGJ2Njfxl1shMYZ7+y798UpsQAaAfTygKB7a0nEwAAAAAAAAAAAAAAAMeiBL2/6YP82NjmHQK0ddQHP/l+AAAAAAAAAOoBAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJUC+QAAAAAAAAAAAAAAAAA3uVms/6Z+NmTS6ru3aKY1bdriGgnEwAAAAAAAAAAAAAAAPRQs4zM/c+tL5j35LtTMVGi+wDpJxQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==):
    // echo "YOUR_BASE64_STRING" | base64 --decode | xxd -p -c 1000

    // Paste the FULL hex‑encoded VAA from the transferTokens transaction here
    bytes vaa =
        hex"0100000000010028a3aedfc7c0dab1c8b87a06ae1c5da28a5b3c4a7245f0d827298cf2bc239b204cdec8136e501e0bc4636365d32ba96cbb3c56183d47efcccb2bf14924b53425006807e60a00000000271400000000000000000000000086f55a04690fd7815a3d802bd587e83ea888b239000000000000011701010000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000dee566b3fe99f8d9934baaeedda298d5b76b886827130000000000000000000000001e6869b8575eee383112ac5c830df7b0fae43eb027130000000000000000000000000000000000000000000000000000000000000000";

    function run() external {
        require(
            vaa.length > 0,
            "VAA hex string is empty. Please paste the transfer VAA."
        );
        require(
            WRAPPED_TOKEN_ADDRESS != address(0),
            "Wrapped token address is not set."
        );

        console.log("Completing Token Transfer on Base Sepolia...");
        console.log("  Token Bridge:", TOKEN_BRIDGE);
        console.log("  Recipient:", RECIPIENT_ADDRESS);
        console.log("  Wrapped Token:", WRAPPED_TOKEN_ADDRESS);

        uint256 balanceBefore = 0;
        try IERC20(WRAPPED_TOKEN_ADDRESS).balanceOf(RECIPIENT_ADDRESS) returns (
            uint256 bal
        ) {
            balanceBefore = bal;
            console.log("  Recipient balance before:", balanceBefore);
        } catch {
            console.log("  Could not query initial balance of wrapped token.");
        }

        vm.startBroadcast();

        ITokenBridge bridge = ITokenBridge(TOKEN_BRIDGE);

        // Call completeTransfer
        console.log("  Calling completeTransfer...");
        bridge.completeTransferWithPayload(vaa);
        console.log("  completeTransfer called successfully.");

        vm.stopBroadcast();

        uint256 balanceAfter = 0;
        try IERC20(WRAPPED_TOKEN_ADDRESS).balanceOf(RECIPIENT_ADDRESS) returns (
            uint256 bal
        ) {
            balanceAfter = bal;
            console.log("  Recipient balance after:", balanceAfter);
            console.log(
                "  Tokens minted/released:",
                balanceAfter - balanceBefore
            );
        } catch {
            console.log(
                "  Could not query final balance of wrapped token. Check explorer."
            );
        }

        console.log("==== Operation Complete ====");
        console.log(
            "Transfer completed. Check recipient balance on Base Sepolia."
        );
    }
}
