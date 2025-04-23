// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol"; // For checking balance

contract CompleteTransfer is Script {
    // --- CONFIGURATION (Destination Chain - Base Sepolia) ---
    address constant TOKEN_BRIDGE = 0x86F55A04690fd7815A3D802bD587e83eA888B239; // Token Bridge on Base Sepolia
    address constant RECIPIENT_ADDRESS =
        0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // The recipient address specified in the TransferTokens script
    address constant WRAPPED_TOKEN_ADDRESS =
        0x266e5B7fb5D918E5A3b2aEde73c2C694cF58E537; // The address of the wrapped token deployed by createWrapped

    // --- VAA ---

    // Get hex-encoded VAA (f.e.: AQAAAAABAGKNsn30EWdX3FH2S/4OGnhKTKVSq62fXzsic7bRE5UVeVKbzbaGjRb6ULF4wAQGJ2Njfxl1shMYZ7+y798UpsQAaAfTygKB7a0nEwAAAAAAAAAAAAAAAMeiBL2/6YP82NjmHQK0ddQHP/l+AAAAAAAAAOoBAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJUC+QAAAAAAAAAAAAAAAAA3uVms/6Z+NmTS6ru3aKY1bdriGgnEwAAAAAAAAAAAAAAAPRQs4zM/c+tL5j35LtTMVGi+wDpJxQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==):
    // echo "YOUR_BASE64_STRING" | base64 --decode | xxd -p -c 1000

    // Paste the FULL hex‑encoded VAA from the transferTokens transaction here
    bytes vaa =
        hex"01000000000100628db27df4116757dc51f64bfe0e1a784a4ca552abad9f5f3b2273b6d113951579529bcdb6868d16fa50b178c004062763637f1975b2131867bfb2efdf14a6c4006807d3ca0281edad2713000000000000000000000000c7a204bdbfe983fcd8d8e61d02b475d4073ff97e00000000000000ea010100000000000000000000000000000000000000000000000000000002540be400000000000000000000000000dee566b3fe99f8d9934baaeedda298d5b76b88682713000000000000000000000000f450b38cccfdcfad2f98f7e4bb533151a2fb00e927140000000000000000000000000000000000000000000000000000000000000000";

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
        bridge.completeTransfer(vaa);
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
