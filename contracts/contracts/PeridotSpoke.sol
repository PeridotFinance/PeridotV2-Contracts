// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// UPGRADEABLE IMPORTS
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeReceiver.sol";

// Inherit from Initializable and OwnableUpgradeable
contract PeridotSpoke is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
    IWormholeReceiver
{
    using SafeERC20 for IERC20;

    // Custom errors
    error InvalidAddress(string param);
    error InvalidAmount();
    error InsufficientValue();
    error OnlyRelayer();
    error MessageProcessingFailed();
    error TokenBridgeTransferFailed();

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

    // Constructor sets IMMUTABLE variables ONLY
    constructor(
        address _wormhole,
        address _relayer,
        address _tokenBridge,
        uint16 _hubChainId,
        address _hubAddress // DO NOT call Ownable/OwnableUpgradeable constructor here
    ) {
        // Input validation remains
        if (_wormhole == address(0)) revert InvalidAddress("wormhole");
        if (_relayer == address(0)) revert InvalidAddress("relayer");
        if (_tokenBridge == address(0)) revert InvalidAddress("token bridge");
        if (_hubAddress == address(0)) revert InvalidAddress("hub address");

        // Set immutable variables
        wormhole = IWormhole(_wormhole);
        relayer = IWormholeRelayerSend(_relayer);
        tokenBridge = ITokenBridge(_tokenBridge);
        hubChainId = _hubChainId;
        hubAddress = _hubAddress;
        // No Ownable init here
    }

    // --- Initializer Function --- //
    // This MUST be called ON THE PROXY after deployment
    function initialize(address initialOwner) external initializer {
        // Initialize OwnableUpgradeable
        __Ownable_init(initialOwner);
        // Initialize ReentrancyGuard (if needed, check OZ docs for upgradeable version)
        // __ReentrancyGuard_init();
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

        // --- Calculate Fees ---
        (uint256 relayerCost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );
        uint256 wormholeFee = wormhole.messageFee();
        uint256 totalFee = relayerCost + wormholeFee;

        // --- Check Sent Value ---
        if (msg.value < totalFee) revert InsufficientValue();

        // --- Token Handling ---
        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve token bridge to spend tokens
        IERC20(token).approve(address(tokenBridge), amount);

        // --- Wormhole Actions ---
        // Call the token bridge to transfer tokens, paying the Wormhole message fee
        uint64 transferSequence = tokenBridge.transferTokens{
            value: wormholeFee
        }(
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

        // Send the message to the hub, paying the relayer fee
        // Use msg.value - wormholeFee to avoid overspending if user sent extra
        uint64 sequence = relayer.sendPayloadToEvm{value: relayerCost}(
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

        // --- Calculate Fees ---
        (uint256 relayerCost, ) = relayer.quoteEVMDeliveryPrice(
            hubChainId,
            0, // No additional native tokens to send
            GAS_LIMIT
        );
        uint256 wormholeFee = wormhole.messageFee();
        uint256 totalFee = relayerCost + wormholeFee;

        // --- Check Sent Value ---
        if (msg.value < totalFee) revert InsufficientValue();

        // --- Token Handling ---
        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve token bridge to spend tokens
        IERC20(token).approve(address(tokenBridge), amount);

        // --- Wormhole Actions ---
        // Call the token bridge to transfer tokens, paying the Wormhole message fee
        uint64 transferSequence = tokenBridge.transferTokens{
            value: wormholeFee
        }(
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

        // Send the message to the hub, paying the relayer fee
        // Use msg.value - wormholeFee to avoid overspending if user sent extra
        uint64 sequence = relayer.sendPayloadToEvm{value: relayerCost}(
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
    ) external payable nonReentrant {
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
                    // Token transfer failed - Revert
                    revert TokenBridgeTransferFailed();
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
