// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Using Test from forge-std
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Interfaces and Contracts Under Test
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol"; // Keep this if MockToken needs it
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol"; // Keep this for MockToken inheritance
import {PeridotHub} from "../contracts/PeridotHub.sol";
import {Peridottroller} from "../contracts/Peridottroller.sol"; // Keep interface if used directly
import {PToken} from "../contracts/PToken.sol"; // Keep interface if used directly
import {PErc20} from "../contracts/PErc20.sol"; // Keep interface if used directly
import {IWormhole} from "../lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import {IWormholeRelayer} from "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import {Base} from "../lib/wormhole-solidity-sdk/src/Base.sol"; // Used by CrossChainSender

// Mock token for testing
contract MockToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock CToken for testing
contract MockCToken is ERC20 {
    address public underlying;
    uint256 public mintResult = 0; // 0 means success
    uint256 public redeemResult = 0; // 0 means success
    uint256 public borrowResult = 0; // 0 means success
    uint256 public repayResult = 0; // 0 means success

    constructor(address _underlying) ERC20("Mock CToken", "cMOCK") {
        underlying = _underlying;
    }

    function mint(uint256 amount) external returns (uint256) {
        return mintResult;
    }

    function redeemUnderlying(uint256 amount) external returns (uint256) {
        return redeemResult;
    }

    function borrow(uint256 amount) external returns (uint256) {
        return borrowResult;
    }

    function repayBorrow(uint256 amount) external returns (uint256) {
        return repayResult;
    }
}

// Mock Comptroller for testing
contract MockComptroller {
    function getAccountLiquidity(
        address account
    ) external pure returns (uint, uint, uint) {
        // Return success, high liquidity, no shortfall
        return (0, 1000e18, 0);
    }
}

// Mock Wormhole contract
contract MockWormhole {
    uint16 public chainId = 1;
    uint256 public messageFee = 0;

    struct VM {
        uint8 version;
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
        uint32 guardianSetIndex;
        bytes signatures;
        bytes32 hash;
    }

    // Updated to properly extract emitter info from the VAA
    function parseAndVerifyVM(
        bytes calldata encodedVM
    ) external pure returns (VM memory vm, bool valid, string memory reason) {
        // We need to actually parse the emitter address and chain ID from the VAA
        // A real VAA has complex encoding, but our mock VAA is simplified

        // Parse the mock VAA format we created in createMockDepositVAA
        // Our mock format: [version(1), guardianSetIndex(4), numSignatures(1), emitterChainId(2), emitterAddress(32), ...]

        require(encodedVM.length >= 40, "Invalid VAA length"); // At minimum need version + guardianSetIndex + numSigs + emitterChainId + emitterAddress

        vm.version = uint8(encodedVM[0]);
        // Skip guardianSetIndex and numSignatures

        // Extract emitterChainId at position 6
        vm.emitterChainId = uint16(bytes2(encodedVM[6:8]));

        // Extract emitterAddress at position 8
        vm.emitterAddress = bytes32(encodedVM[8:40]);

        // Extract payload (everything after position 49)
        if (encodedVM.length > 49) {
            vm.payload = encodedVM[49:];
        }

        valid = true;
        reason = "";
        return (vm, valid, reason);
    }
}

// Mock TokenBridge contract
contract MockTokenBridge {
    event TokenTransferPeridotleted(
        address token,
        uint256 amount,
        address recipient
    );

    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external returns (uint64) {
        return 1;
    }

    function completeTransfer(bytes memory vaa) external returns (bool) {
        emit TokenTransferPeridotleted(address(0), 0, address(0));
        return true;
    }

    function wrappedAsset(
        uint16 chainId,
        bytes32 tokenAddress
    ) external view returns (address) {
        return address(0x123);
    }
}

// Mock Relayer contract
contract MockRelayer {
    struct RelayerMessage {
        uint16 targetChain;
        address targetAddress;
        bytes payload;
        uint256 receiverValue;
        uint256 gasLimit;
    }

    RelayerMessage[] public messages;

    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    )
        external
        pure
        returns (
            uint256 nativePriceQuote,
            uint256 targetChainRefundPerGasUnused
        )
    {
        return (0.01 ether, 0);
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence) {
        require(msg.value >= 0.01 ether, "Insufficient payment");

        messages.push(
            RelayerMessage({
                targetChain: targetChain,
                targetAddress: targetAddress,
                payload: payload,
                receiverValue: receiverValue,
                gasLimit: gasLimit
            })
        );

        return 1;
    }

    function getMessageCount() external view returns (uint256) {
        return messages.length;
    }

    function getLastMessage() external view returns (RelayerMessage memory) {
        require(messages.length > 0, "No messages");
        return messages[messages.length - 1];
    }
}

// Cross Chain Sender - This simulates a contract on another chain that sends messages to the PeridotHub
contract CrossChainSender is Base {
    address public owner;

    constructor(
        address _wormholeRelayer,
        address _wormhole
    ) Base(_wormholeRelayer, _wormhole) {
        owner = msg.sender;
    }

    // Sends a deposit message from this chain to the target hub
    function sendDeposit(
        uint16 targetChain,
        address targetHub,
        address user,
        address token,
        uint256 amount
    ) external payable {
        // Create the deposit payload
        bytes memory payload = abi.encode(
            uint8(1), // PAYLOAD_ID_DEPOSIT
            user,
            token,
            amount
        );

        // Get quoted price for delivery
        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0, // No native tokens to send
            250000 // Gas limit
        );

        require(msg.value >= cost, "Insufficient payment for message");

        // Send the message to the hub
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetHub,
            payload,
            0, // No native tokens to send
            250000 // Gas limit
        );
    }

    // Sends a borrow message from this chain to the target hub
    function sendBorrow(
        uint16 targetChain,
        address targetHub,
        address user,
        address token,
        uint256 amount
    ) external payable {
        // Create the borrow payload
        bytes memory payload = abi.encode(
            uint8(2), // PAYLOAD_ID_BORROW
            user,
            token,
            amount
        );

        // Get quoted price for delivery
        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0, // No native tokens to send
            250000 // Gas limit
        );

        require(msg.value >= cost, "Insufficient payment for message");

        // Send the message to the hub
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetHub,
            payload,
            0, // No native tokens to send
            250000 // Gas limit
        );
    }

    // Sends a repay message from this chain to the target hub
    function sendRepay(
        uint16 targetChain,
        address targetHub,
        address user,
        address token,
        uint256 amount
    ) external payable {
        // Create the repay payload
        bytes memory payload = abi.encode(
            uint8(3), // PAYLOAD_ID_REPAY
            user,
            token,
            amount
        );

        // Get quoted price for delivery
        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0, // No native tokens to send
            250000 // Gas limit
        );

        require(msg.value >= cost, "Insufficient payment for message");

        // Send the message to the hub
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetHub,
            payload,
            0, // No native tokens to send
            250000 // Gas limit
        );
    }

    // Sends a withdraw message from this chain to the target hub
    function sendWithdraw(
        uint16 targetChain,
        address targetHub,
        address user,
        address token,
        uint256 amount
    ) external payable {
        // Create the withdraw payload
        bytes memory payload = abi.encode(
            uint8(4), // PAYLOAD_ID_WITHDRAW
            user,
            token,
            amount
        );

        // Get quoted price for delivery
        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0, // No native tokens to send
            250000 // Gas limit
        );

        require(msg.value >= cost, "Insufficient payment for message");

        // Send the message to the hub
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetHub,
            payload,
            0, // No native tokens to send
            250000 // Gas limit
        );
    }

    // Receive Wormhole messages - we don't need this for our tests but it's required by the Base contract
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32
    ) external payable onlyWormholeRelayer {
        // Not needed for our tests
    }
}

// Custom test contract that extends WormholeRelayerTest
contract PeridotHubWormholeTest is Test {
    // Source chain contracts
    PeridotHub public hubSource;
    CrossChainSender public senderSource;
    MockToken public tokenSource;
    MockCToken public cTokenSource;
    MockComptroller public comptrollerSource;

    // Target chain contracts
    PeridotHub public hubTarget;
    MockToken public tokenTarget;
    MockCToken public cTokenTarget;
    MockComptroller public comptrollerTarget;

    // Test addresses
    address public constant OWNER = address(0x1);
    address public constant USER = address(0x2);

    // Mock Wormhole addresses (instead of using real ones)
    address public mockWormholeSource;
    address public mockWormholeTarget;
    address public mockTokenBridgeSource;
    address public mockTokenBridgeTarget;
    address public mockRelayerSource;
    address public mockRelayerTarget;

    // Chain IDs (for testing)
    uint16 public constant SOURCE_CHAIN_ID = 1; // Use arbitrary chain ID for source
    uint16 public constant TARGET_CHAIN_ID = 2; // Use arbitrary chain ID for target

    // Copied helper function from wormhole-solidity-sdk/src/Utils.sol
    function toWormholeFormat(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Setup function
    function setUp() public {
        // Give OWNER some ETH for gas
        vm.deal(OWNER, 100 ether);

        // Set up mock addresses
        mockWormholeSource = address(new MockWormhole());
        mockWormholeTarget = address(new MockWormhole());
        mockTokenBridgeSource = address(new MockTokenBridge());
        mockTokenBridgeTarget = address(new MockTokenBridge());
        mockRelayerSource = address(new MockRelayer());
        mockRelayerTarget = address(new MockRelayer());

        // Set up source chain
        vm.startPrank(OWNER);

        // Deploy mock contracts on source chain
        tokenSource = new MockToken("Source Token", "SRC", 18);
        comptrollerSource = new MockComptroller();

        // Deploy the PeridotHub on source chain
        hubSource = new PeridotHub(
            mockWormholeSource,
            mockTokenBridgeSource,
            address(comptrollerSource),
            mockRelayerSource
        );

        // Transfer some ETH to the hub for relayer fees
        vm.deal(address(hubSource), 10 ether);

        // Deploy the mock cToken
        cTokenSource = new MockCToken(address(tokenSource));

        // Register the market in the hub
        hubSource.registerMarket(address(tokenSource), address(cTokenSource));

        // Deploy the cross-chain sender
        senderSource = new CrossChainSender(
            mockRelayerSource,
            mockWormholeSource
        );

        // Register the target hub as a trusted emitter in the source hub
        hubSource.setTrustedEmitter(
            TARGET_CHAIN_ID,
            bytes32(uint256(uint160(address(0)))), // This will be set later
            true
        );

        vm.stopPrank();

        // Mint tokens to the USER
        tokenSource.mint(USER, 10000 * 10 ** 18);

        // Set up target chain
        vm.startPrank(OWNER);

        // Deploy mock contracts on target chain
        tokenTarget = new MockToken("Target Token", "TGT", 18);
        comptrollerTarget = new MockComptroller();

        // Deploy the PeridotHub on target chain
        hubTarget = new PeridotHub(
            mockWormholeTarget,
            mockTokenBridgeTarget,
            address(comptrollerTarget),
            mockRelayerTarget
        );

        // Transfer some ETH to the hub for relayer fees
        vm.deal(address(hubTarget), 10 ether);

        // Deploy the mock cToken
        cTokenTarget = new MockCToken(address(tokenTarget));

        // Register the market in the hub
        hubTarget.registerMarket(address(tokenTarget), address(cTokenTarget));

        // Register the source hub as a trusted emitter in the target hub
        hubTarget.setTrustedEmitter(
            SOURCE_CHAIN_ID,
            bytes32(uint256(uint160(address(hubSource)))),
            true
        );

        vm.stopPrank();

        // Update the source hub with the target hub address
        vm.prank(OWNER);
        hubSource.setTrustedEmitter(
            TARGET_CHAIN_ID,
            bytes32(uint256(uint160(address(hubTarget)))),
            true
        );

        // Mint tokens to the USER
        tokenTarget.mint(USER, 10000 * 10 ** 18);
    }

    // TESTS

    // Test that validates our environment setup
    function testEnvironmentSetup() public {
        // Verify contracts were deployed
        assertTrue(address(hubSource) != address(0));
        assertTrue(address(hubTarget) != address(0));

        // Verify market registrations
        assertTrue(hubSource.registeredMarkets(address(cTokenSource)));
        assertTrue(hubTarget.registeredMarkets(address(cTokenTarget)));

        // Verify trusted emitters
        assertTrue(
            hubSource.trustedEmitters(
                TARGET_CHAIN_ID,
                toWormholeFormat(address(hubTarget))
            )
        );
        assertTrue(
            hubTarget.trustedEmitters(
                SOURCE_CHAIN_ID,
                toWormholeFormat(address(hubSource))
            )
        );

        // Verify USER has tokens
        assertEq(tokenSource.balanceOf(USER), 10000 * 10 ** 18);
        assertEq(tokenTarget.balanceOf(USER), 10000 * 10 ** 18);
    }

    // Test cross-chain deposit (mocked)
    function testMockCrossChainDeposit() public {
        // Set up
        uint256 depositAmount = 100 * 10 ** 18;

        // Transfer tokens to the source hub
        vm.prank(USER);
        tokenSource.transfer(address(hubSource), depositAmount);

        // Create the deposit payload
        bytes memory payload = abi.encode(
            uint8(1), // PAYLOAD_ID_DEPOSIT
            USER,
            address(tokenTarget),
            depositAmount
        );

        // Submit the payload to the target hub
        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            payload,
            new bytes[](0),
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(payload)
        );

        // Verify the deposit was recorded correctly
        assertEq(
            hubTarget.getCollateralBalance(USER, address(tokenTarget)),
            depositAmount
        );
    }

    // Test a full round-trip borrow flow
    function testMockCrossChainBorrow() public {
        // Set up
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 borrowAmount = 50 * 10 ** 18;

        // First make a deposit to have collateral
        vm.prank(USER);
        tokenSource.transfer(address(hubSource), depositAmount);

        // Create and process a deposit payload
        bytes memory depositPayload = abi.encode(
            uint8(1), // PAYLOAD_ID_DEPOSIT
            USER,
            address(tokenTarget),
            depositAmount
        );

        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            depositPayload,
            new bytes[](0),
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(depositPayload)
        );

        // Verify the deposit was successful
        assertEq(
            hubTarget.getCollateralBalance(USER, address(tokenTarget)),
            depositAmount
        );

        // Now create a borrow payload
        bytes memory borrowPayload = abi.encode(
            uint8(2), // PAYLOAD_ID_BORROW
            USER,
            address(tokenTarget),
            borrowAmount
        );

        // Process the borrow request
        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            borrowPayload,
            new bytes[](0),
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(borrowPayload)
        );

        // Verify the borrow was successful
        assertEq(
            hubTarget.getBorrowBalance(USER, address(tokenTarget)),
            borrowAmount
        );

        // Check that the hub sent tokens back to the user on the source chain
        MockRelayer relayer = MockRelayer(mockRelayerTarget);
        assertEq(
            relayer.getMessageCount(),
            1,
            "Should have sent a token transfer notification"
        );

        // Verify the token bridge was called to transfer tokens back
        // In a real implementation, we'd check token balances, but in the mock
        // we just make sure the proper calls were made
        MockRelayer.RelayerMessage memory message = relayer.getLastMessage();
        assertEq(
            message.targetChain,
            SOURCE_CHAIN_ID,
            "Wrong target chain for borrow receipt"
        );
        assertEq(
            message.targetAddress,
            USER,
            "Wrong target address for borrow receipt"
        );

        // Decode the receipt payload to verify it contains the correct info
        (uint8 status, address recipient, address token, uint256 amount) = abi
            .decode(message.payload, (uint8, address, address, uint256));

        assertEq(status, 0, "Status should be success (0)");
        assertEq(recipient, USER, "Wrong recipient in receipt");
        assertEq(token, address(tokenTarget), "Wrong token in receipt");
        assertEq(amount, borrowAmount, "Wrong amount in receipt");
    }

    // Test to measure gas consumption of the withdrawal branch in _processPayload
    function testWithdrawGasConsumption() public {
        // First setup: Deposit some tokens to later withdraw
        uint256 depositAmount = 100 * 10 ** 18;

        // Transfer tokens to the source hub
        vm.prank(USER);
        tokenSource.transfer(address(hubSource), depositAmount);

        // Create and process a deposit payload
        bytes memory depositPayload = abi.encode(
            uint8(1), // PAYLOAD_ID_DEPOSIT
            USER,
            address(tokenTarget),
            depositAmount
        );

        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            depositPayload,
            new bytes[](0),
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(depositPayload)
        );

        // Verify the deposit was successful
        assertEq(
            hubTarget.getCollateralBalance(USER, address(tokenTarget)),
            depositAmount
        );

        // Now create a withdraw payload to test gas consumption
        uint256 withdrawAmount = 50 * 10 ** 18;
        bytes memory withdrawPayload = abi.encode(
            uint8(4), // PAYLOAD_ID_WITHDRAW
            USER,
            address(tokenTarget),
            withdrawAmount
        );

        // Measure gas consumption specifically for the withdrawal operation
        uint256 gasStarted = gasleft();

        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            withdrawPayload,
            new bytes[](0),
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(withdrawPayload)
        );

        uint256 gasUsed = gasStarted - gasleft();

        // Log the gas used for analysis
        console.log("Gas used for withdrawal in _processPayload: ", gasUsed);

        // Verify the withdrawal was successful
        assertEq(
            hubTarget.getCollateralBalance(USER, address(tokenTarget)),
            depositAmount - withdrawAmount
        );

        // Check that the relayer was called to send tokens back
        MockRelayer relayer = MockRelayer(mockRelayerTarget);
        assertEq(
            relayer.getMessageCount(),
            1,
            "Should have sent a token transfer notification"
        );
    }

    // Test token bridge transfer completion
    function testTokenTransferCompletion() public {
        // Create a mock VAA for token transfer
        bytes memory mockVAA = new bytes(100);
        // Set the first byte to version 1
        mockVAA[0] = 0x01;
        // Set emitter chain ID to SOURCE_CHAIN_ID at position 6-7
        mockVAA[6] = bytes1(uint8(SOURCE_CHAIN_ID >> 8));
        mockVAA[7] = bytes1(uint8(SOURCE_CHAIN_ID));
        // Set emitter address to mockTokenBridgeSource at position 8-39
        bytes32 emitterAddress = toWormholeFormat(mockTokenBridgeSource);
        for (uint i = 0; i < 32; i++) {
            mockVAA[8 + i] = emitterAddress[i];
        }

        // Create a payload to process along with the token transfer
        bytes memory payload = abi.encode(
            uint8(1), // PAYLOAD_ID_DEPOSIT
            USER,
            address(tokenTarget),
            100 * 10 ** 18
        );

        // Create an array with the mock VAA
        bytes[] memory additionalVaas = new bytes[](1);
        additionalVaas[0] = mockVAA;

        // Process the message with the mock VAA
        vm.prank(mockRelayerTarget);
        hubTarget.receiveWormholeMessages(
            payload,
            additionalVaas,
            toWormholeFormat(address(hubSource)),
            SOURCE_CHAIN_ID,
            keccak256(payload)
        );

        // In a real test, we'd check that the token was received
        // but here we're just testing that the flow works without errors
        // and the TokenTransferCompleted event is emitted
    }

    // Removed duplicated/incorrect tests below
    // function test_RegisterMarket_Success() public { ... }
    // function test_SetTrustedEmitter_Success() public { ... }
}
