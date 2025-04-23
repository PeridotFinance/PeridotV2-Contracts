// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IWormhole} from "../lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";

contract AttestToken is Script {
    // — fill in your deployed addresses:
    address constant WORMHOLE = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35; // Wormhole core on Arbitrum Sepolia
    address constant TOKEN_BRIDGE = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e; // Wormhole TokenBridge on Arbitrum Sepolia
    address constant TOKEN_TO_ATTEST =
        0xDEe566b3Fe99F8d9934BAAEEdDA298D5B76B8868; // Your ERC20 address on Arbitrum
    uint32 constant NONCE = 42069420; // any unique uint32

    function run() external {
        console.log(" Attesting token on Arbitrum Sepolia");
        console.log(" Wormhole:", WORMHOLE);
        console.log(" TokenBridge:", TOKEN_BRIDGE);
        console.log(" Token to attest:", TOKEN_TO_ATTEST);

        vm.startBroadcast();

        // 1) figure out the Wormhole message fee
        uint256 msgFee = IWormhole(WORMHOLE).messageFee();
        console.log(" Wormhole message fee:", msgFee);

        // 2) call attestToken, paying exactly the messageFee
        uint64 sequence = ITokenBridge(TOKEN_BRIDGE).attestToken{value: msgFee}(
            TOKEN_TO_ATTEST,
            NONCE
        );
        console.log(" attestToken sequence:", sequence);

        vm.stopBroadcast();

        // Emitter info for fetching the VAA:
        bytes32 emitter = bytes32(uint256(uint160(TOKEN_BRIDGE)));
        console.log(" Emitter   (bytes32):");
        console.logBytes32(emitter);
        console.log(" Sequence  :", sequence);
        console.log(
            " Now run: wormhole-client query vaa <chainId> <emitter> <sequence>"
        );
    }
}
