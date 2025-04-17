# Wormhole Solidity SDK Quick Reference

This document summarizes key components of the `wormhole-solidity-sdk` for easier integration.

## Core Interfaces (`src/interfaces/`)

These define the primary interaction points with the Wormhole protocol:

- `IWormhole.sol`:
  - Handles core Wormhole functions like VAA parsing and verification.
  - Key function: `parseAndVerifyVM(bytes memory encodedVM) returns (VM memory vm, bool valid, string memory reason)` - Verifies a VAA and returns its parsed contents.
  - Key function: `publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel) returns (uint64 sequence)` - Publishes a message to Wormhole (less common when using Relayer).
- `IWormholeReceiver.sol`:
  - Interface that contracts must implement to receive messages via the Wormhole Relayer.
  - Key function: `receiveWormholeMessages(bytes memory payload, bytes[] memory additionalVaas, bytes32 sourceAddress, uint16 sourceChain, bytes32 deliveryHash)` - Entry point for relayed messages.
- `IWormholeRelayer.sol`:
  - Interface for interacting with the Wormhole Generic Relayer service.
  - Defines interfaces like `IWormholeRelayerSend` used by contracts sending messages.
  - Key function (`IWormholeRelayerSend`): `sendPayloadToEvm(uint16 targetChain, address targetAddress, bytes memory payload, uint256 receiverValue, uint256 gasLimit) payable returns (uint64 sequence)` - Sends a payload to a target chain via the relayer.
  - Key function (`IWormholeRelayerSend`): `quoteEVMDeliveryPrice(uint16 targetChain, uint256 receiverValue, uint256 gasLimit) view returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused)` - Gets the cost for relaying a message.
- `ITokenBridge.sol`:
  - Interface for interacting with the Wormhole Token Bridge.
  - Key function: `transferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce) payable returns (uint64 sequence)` - Initiates a cross-chain token transfer.
  - Key function: `completeTransfer(bytes memory encodedVm)` - Completes a token transfer initiated on another chain using the VAA.

## Relayer SDK (`src/WormholeRelayer/`)

Provides base contracts to simplify development with the Wormhole Relayer:

- `Base.sol`: Basic helpers, modifiers (`onlyWormholeRelayer`), and sender registration.
- `TokenBase.sol`: Extends `Base.sol` with helpers for sending/receiving tokens via the relayer (`transferTokenToTarget`). Includes `TokenSender` and `TokenReceiver` abstract contracts.
- `CCTPBase.sol`: Similar to `TokenBase.sol` but for Circle's CCTP.
- `CCTPAndTokenBase.sol`: Combines `TokenBase` and `CCTPBase`.

## Utilities (`src/Utils.sol`)

- Contains helper **free functions** (defined outside a library/contract).
- **Note:** In Solidity >=0.7.0, these functions are internal to `Utils.sol` and cannot be called directly (e.g., `Utils.toWormholeFormat`) from other contracts after import.
- **Usage:** To use these functions, you must copy their implementation directly into your contract or a local helper library within your project.
- Key function: `toWormholeFormat(address addr) pure returns (bytes32)` - Converts an EVM address to the `bytes32` format used by Wormhole.
- Key function: `fromWormholeFormat(bytes32 whFormatAddress) pure returns (address)` - Converts a `bytes32` Wormhole address back to an EVM `address`.

## Constants (`src/constants/`)

- `Chains.sol`: Defines Wormhole Chain IDs.

## Installation / Setup

- Use Foundry: `forge install wormhole-foundation/wormhole-solidity-sdk@<version>`
- Add remappings to `remappings.txt` (usually done automatically by forge).
- Consider setting `evm_version` in `foundry.toml` (e.g., `"paris"`) for compatibility if targeting chains with older EVM versions.
