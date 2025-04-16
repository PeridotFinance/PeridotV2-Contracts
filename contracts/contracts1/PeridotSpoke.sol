// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";

contract PeridotSpoke is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Custom errors
    error InvalidAddress(string param);
    error InvalidAmount();
    error InsufficientValue();
    error OnlyRelayer();
    error MessageProcessingFailed();

    // Constants
    uint8 private constant PAYLOAD_ID_DEPOSIT = 1;
    uint8 private constant PAYLOAD_ID_BORROW = 2;
    uint8 private constant PAYLOAD_ID_REPAY = 3;
    uint8 private constant PAYLOAD_ID_WITHDRAW = 4;
    uint256 private constant GAS_LIMIT = 1000000; // Increased gas limit for cross-chain calls

    // Wormhole integration
    IWormhole public immutable wormhole;
    IWormholeRelayerSend public immutable relayer;
    ITokenBridge public immutable tokenBridge;

    // Hub chain configuration
    uint16 public immutable hubChainId;
    address public immutable hubAddress;

    mapping(bytes32 => bool) public processedMessages;

    // Events
    event DepositInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint64 sequence
    );
    event BorrowInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint64 sequence
    );
    event RepayInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint64 sequence
    );
    event WithdrawInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint64 sequence
    );
    event DeliveryStatus(uint8 status, bytes32 deliveryHash);
    event AssetReceived(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(
        address _wormhole,
        address _relayer,
        address _tokenBridge,
        uint16 _hubChainId,
        address _hubAddress
    ) Ownable(msg.sender) {
        if (_wormhole == address(0)) revert InvalidAddress("wormhole");
        if (_relayer == address(0)) revert InvalidAddress("relayer");
        if (_tokenBridge == address(0)) revert InvalidAddress("token bridge");
        if (_hubAddress == address(0)) revert InvalidAddress("hub address");

        wormhole = IWormhole(_wormhole);
        relayer = IWormholeRelayerSend(_relayer);
        tokenBridge = ITokenBridge(_tokenBridge);
        hubChainId = _hubChainId;
        hubAddress = _hubAddress;
    }

    // Helper function to convert address to bytes32
    function toWormholeFormat(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Helper function to create payload
    function _createPayload(
        uint8 payloadId,
        address user,
        address token,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(payloadId, user, token, amount);
    }

    // Deposit function
    function deposit(
        address token,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // First transfer the token to the token bridge via wormhole
        IERC20(token).approve(address(tokenBridge), amount);

        // Call the token bridge to transfer tokens
        uint64 transferSequence = tokenBridge.transferTokens(
            token,
            amount,
            hubChainId,
            toWormholeFormat(hubAddress),
            0, // dust
            0 // nonce
        );

        // Create payload for the message
        bytes memory payload = _createPayload(
            PAYLOAD_ID_DEPOSIT,
            msg.sender,
            token,
            amount
        );

        // Get delivery cost from the relayer
        (uint256 cost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        if (msg.value < cost) revert InsufficientValue();

        // Send the message to the hub
        uint64 sequence = relayer.sendPayloadToEvm{value: cost}(
            hubChainId,
            hubAddress,
            payload,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        emit DepositInitiated(msg.sender, token, amount, sequence);
    }

    // Borrow function
    function borrow(
        address token,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Create payload
        bytes memory payload = _createPayload(
            PAYLOAD_ID_BORROW,
            msg.sender,
            token,
            amount
        );

        // Get delivery cost from the relayer
        (uint256 cost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        if (msg.value < cost) revert InsufficientValue();

        // Send the message to the hub
        uint64 sequence = relayer.sendPayloadToEvm{value: cost}(
            hubChainId,
            hubAddress,
            payload,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        emit BorrowInitiated(msg.sender, token, amount, sequence);
    }

    // Repay function
    function repay(
        address token,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve token bridge to spend tokens
        IERC20(token).approve(address(tokenBridge), amount);

        // Call the token bridge to transfer tokens
        uint64 transferSequence = tokenBridge.transferTokens(
            token,
            amount,
            hubChainId,
            toWormholeFormat(hubAddress),
            0, // dust
            0 // nonce
        );

        // Create payload
        bytes memory payload = _createPayload(
            PAYLOAD_ID_REPAY,
            msg.sender,
            token,
            amount
        );

        // Get delivery cost from the relayer
        (uint256 cost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        if (msg.value < cost) revert InsufficientValue();

        // Send the message to the hub
        uint64 sequence = relayer.sendPayloadToEvm{value: cost}(
            hubChainId,
            hubAddress,
            payload,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        emit RepayInitiated(msg.sender, token, amount, sequence);
    }

    // Withdraw function
    function withdraw(
        address token,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Create payload
        bytes memory payload = _createPayload(
            PAYLOAD_ID_WITHDRAW,
            msg.sender,
            token,
            amount
        );

        // Get delivery cost from the relayer
        (uint256 cost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        if (msg.value < cost) revert InsufficientValue();

        // Send the message to the hub
        uint64 sequence = relayer.sendPayloadToEvm{value: cost}(
            hubChainId,
            hubAddress,
            payload,
            0, // No additional native tokens to send
            GAS_LIMIT
        );

        emit WithdrawInitiated(msg.sender, token, amount, sequence);
    }

    // Add a receiver function to handle delivery status updates and token receipts
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        if (msg.sender != address(relayer)) revert OnlyRelayer();
        if (processedMessages[deliveryHash]) return; // Skip if already processed

        processedMessages[deliveryHash] = true;

        // Process token transfers from additionalVaas
        for (uint i = 0; i < additionalVaas.length; i++) {
            (
                IWormhole.VM memory vm,
                bool valid,
                string memory reason
            ) = wormhole.parseAndVerifyVM(additionalVaas[i]);

            if (!valid) continue; // Skip invalid VAAs

            // Check if this is a token transfer VAA
            if (vm.emitterAddress == toWormholeFormat(address(tokenBridge))) {
                try tokenBridge.completeTransfer(additionalVaas[i]) {
                    // Token transfer completed successfully
                    // We could parse the VAA to get details but for now just emit an event
                    emit AssetReceived(msg.sender, address(0), 0);
                } catch {
                    // Token transfer failed
                }
            }
        }

        // Process payload (status updates, etc.)
        if (payload.length > 0) {
            // Decode the payload to get status information
            // Example implementation - adjust based on your hub's response format
            (uint8 status, address user, address token, uint256 amount) = abi
                .decode(payload, (uint8, address, address, uint256));

            if (user != address(0) && amount > 0) {
                emit AssetReceived(user, token, amount);
            }
        }

        emit DeliveryStatus(0, deliveryHash); // 0 indicates success
    }
}
