// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../lib/forge-std/src/Test.sol";
import {PeridotSpoke} from "../contracts/PeridotSpoke.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/wormhole-solidity-sdk/src/Utils.sol";

// Reuse the MockToken from PeridotHubWormhole.t.sol
contract MockToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** decimals);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock Wormhole Relayer that records calls for testing
contract MockWormholeRelayer {
    struct RelayerMessage {
        uint16 targetChain;
        address targetAddress;
        bytes payload;
        uint256 receiverValue;
        uint256 gasLimit;
    }

    RelayerMessage[] public messages;
    uint64 public nextSequence = 1;

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

        return nextSequence++;
    }

    function getMessageCount() external view returns (uint256) {
        return messages.length;
    }

    function getLastMessage() external view returns (RelayerMessage memory) {
        require(messages.length > 0, "No messages");
        return messages[messages.length - 1];
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

    function parseAndVerifyVM(
        bytes calldata encodedVM
    ) external pure returns (VM memory vm, bool valid, string memory reason) {
        valid = true;
        reason = "";
        return (vm, valid, reason);
    }
}

// Mock TokenBridge contract
contract MockTokenBridge {
    event TokensTransferred(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    );

    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence) {
        // Actually transfer the tokens from the sender to simulate them being bridged
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        emit TokensTransferred(token, amount, recipientChain, recipient);
        return 1;
    }

    function completeTransfer(bytes memory vaa) external returns (bool) {
        return true;
    }

    function wrappedAsset(
        uint16 chainId,
        bytes32 tokenAddress
    ) external pure returns (address) {
        return address(0);
    }
}

contract PeridotSpokeTest is Test {
    // Test contracts
    PeridotSpoke public spoke;
    MockWormholeRelayer public relayer;
    MockWormhole public wormhole;
    MockTokenBridge public tokenBridge;
    MockToken public token;

    // Test addresses
    address public constant OWNER = address(0x1);
    address public constant USER = address(0x2);
    address public constant HUB_ADDRESS = address(0x3);

    // Chain IDs
    uint16 public constant SOURCE_CHAIN_ID = 1;
    uint16 public constant HUB_CHAIN_ID = 2;

    // Test amounts
    uint256 public constant TEST_AMOUNT = 100 * 10 ** 18;

    function setUp() public {
        // Give accounts some ETH balance
        vm.deal(OWNER, 100 ether);
        vm.deal(USER, 100 ether);

        // Deploy mock contracts
        vm.startPrank(OWNER);

        wormhole = new MockWormhole();
        relayer = new MockWormholeRelayer();
        tokenBridge = new MockTokenBridge();
        token = new MockToken("Test Token", "TEST", 18);

        // Deploy the PeridotSpoke contract
        spoke = new PeridotSpoke(
            address(wormhole),
            address(relayer),
            address(tokenBridge),
            HUB_CHAIN_ID,
            HUB_ADDRESS
        );

        vm.stopPrank();

        // Give the USER some tokens
        token.mint(USER, 10000 * 10 ** 18);

        // User approves spoke contract to spend tokens
        vm.prank(USER);
        token.approve(address(spoke), type(uint256).max);
    }

    // Test deposit function
    function testDeposit() public {
        vm.prank(USER);

        // Call the deposit function with value for the relayer fee
        spoke.deposit{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Verify message was sent to relayer
        assertEq(relayer.getMessageCount(), 1);

        // Get the message and verify its contents
        MockWormholeRelayer.RelayerMessage memory message = relayer
            .getLastMessage();
        assertEq(message.targetChain, HUB_CHAIN_ID);
        assertEq(message.targetAddress, HUB_ADDRESS);

        // Decode the payload
        (uint8 payloadId, address user, address tokenAddr, uint256 amount) = abi
            .decode(message.payload, (uint8, address, address, uint256));

        // Verify payload contents
        assertEq(payloadId, 1); // PAYLOAD_ID_DEPOSIT
        assertEq(user, USER);
        assertEq(tokenAddr, address(token));
        assertEq(amount, TEST_AMOUNT);
    }

    // Test borrow function
    function testBorrow() public {
        vm.prank(USER);

        // Call the borrow function with value for the relayer fee
        spoke.borrow{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Verify message was sent to relayer
        assertEq(relayer.getMessageCount(), 1);

        // Get the message and verify its contents
        MockWormholeRelayer.RelayerMessage memory message = relayer
            .getLastMessage();
        assertEq(message.targetChain, HUB_CHAIN_ID);
        assertEq(message.targetAddress, HUB_ADDRESS);

        // Decode the payload
        (uint8 payloadId, address user, address tokenAddr, uint256 amount) = abi
            .decode(message.payload, (uint8, address, address, uint256));

        // Verify payload contents
        assertEq(payloadId, 2); // PAYLOAD_ID_BORROW
        assertEq(user, USER);
        assertEq(tokenAddr, address(token));
        assertEq(amount, TEST_AMOUNT);
    }

    // Test repay function
    function testRepay() public {
        vm.prank(USER);

        // Call the repay function with value for the relayer fee
        spoke.repay{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Verify message was sent to relayer
        assertEq(relayer.getMessageCount(), 1);

        // Get the message and verify its contents
        MockWormholeRelayer.RelayerMessage memory message = relayer
            .getLastMessage();
        assertEq(message.targetChain, HUB_CHAIN_ID);
        assertEq(message.targetAddress, HUB_ADDRESS);

        // Decode the payload
        (uint8 payloadId, address user, address tokenAddr, uint256 amount) = abi
            .decode(message.payload, (uint8, address, address, uint256));

        // Verify payload contents
        assertEq(payloadId, 3); // PAYLOAD_ID_REPAY
        assertEq(user, USER);
        assertEq(tokenAddr, address(token));
        assertEq(amount, TEST_AMOUNT);
    }

    // Test withdraw function
    function testWithdraw() public {
        vm.prank(USER);

        // Call the withdraw function with value for the relayer fee
        spoke.withdraw{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Verify message was sent to relayer
        assertEq(relayer.getMessageCount(), 1);

        // Get the message and verify its contents
        MockWormholeRelayer.RelayerMessage memory message = relayer
            .getLastMessage();
        assertEq(message.targetChain, HUB_CHAIN_ID);
        assertEq(message.targetAddress, HUB_ADDRESS);

        // Decode the payload
        (uint8 payloadId, address user, address tokenAddr, uint256 amount) = abi
            .decode(message.payload, (uint8, address, address, uint256));

        // Verify payload contents
        assertEq(payloadId, 4); // PAYLOAD_ID_WITHDRAW
        assertEq(user, USER);
        assertEq(tokenAddr, address(token));
        assertEq(amount, TEST_AMOUNT);
    }

    // Test handling insufficient fee
    function testInsufficientFee() public {
        vm.prank(USER);

        // Call with insufficient value
        vm.expectRevert(PeridotSpoke.InsufficientValue.selector);
        spoke.deposit{value: 0.001 ether}(address(token), TEST_AMOUNT);
    }

    // Test token transfer happens correctly in deposit
    function testTokenTransferInDeposit() public {
        uint256 initialBalance = token.balanceOf(USER);

        vm.prank(USER);
        spoke.deposit{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Check that user's balance decreased
        assertEq(token.balanceOf(USER), initialBalance - TEST_AMOUNT);

        // Check that tokens were transferred to the spoke contract
        assertEq(token.balanceOf(address(spoke)), 0); // Should be 0 since tokens are transferred to TokenBridge
    }

    // Test token transfer happens correctly in repay
    function testTokenTransferInRepay() public {
        uint256 initialBalance = token.balanceOf(USER);

        vm.prank(USER);
        spoke.repay{value: 0.01 ether}(address(token), TEST_AMOUNT);

        // Check that user's balance decreased
        assertEq(token.balanceOf(USER), initialBalance - TEST_AMOUNT);

        // Check that tokens were transferred to the spoke contract
        assertEq(token.balanceOf(address(spoke)), 0); // Should be 0 since tokens are transferred to TokenBridge
    }

    // Test receiving Wormhole messages
    function testReceiveWormholeMessages() public {
        bytes memory payload = abi.encode(
            0, // status code
            USER,
            address(token),
            TEST_AMOUNT
        );
        bytes[] memory additionalVaas = new bytes[](0);
        bytes32 sourceAddress = bytes32(uint256(uint160(HUB_ADDRESS)));
        uint16 sourceChain = HUB_CHAIN_ID;
        bytes32 deliveryHash = keccak256(payload);

        // Should not revert when called by relayer
        vm.prank(address(relayer));
        spoke.receiveWormholeMessages(
            payload,
            additionalVaas,
            sourceAddress,
            sourceChain,
            deliveryHash
        );

        // Should revert when called by other addresses
        vm.prank(USER);
        vm.expectRevert(PeridotSpoke.OnlyRelayer.selector);
        spoke.receiveWormholeMessages(
            payload,
            additionalVaas,
            sourceAddress,
            sourceChain,
            deliveryHash
        );
    }

    // Test reverting due to insufficient value for borrow, repay, withdraw
    function testRevert_InsufficientValue_BorrowAndWithdraw() public {
        vm.prank(USER);

        // Borrow
        vm.expectRevert(PeridotSpoke.InsufficientValue.selector);
        spoke.borrow{value: 0.001 ether}(address(token), TEST_AMOUNT);

        // Withdraw
        vm.expectRevert(PeridotSpoke.InsufficientValue.selector);
        spoke.withdraw{value: 0.001 ether}(address(token), TEST_AMOUNT);
    }

    // Test reverting due to insufficient value for repay (Isolated)
    function testRevert_InsufficientValue_Repay() public {
        // Explicitly get the cost to verify the condition
        (uint256 cost, ) = relayer.quoteEVMDeliveryPrice(
            HUB_CHAIN_ID,
            0,
            1000000
        ); // Use same params as contract
        uint256 sentValue = 0.001 ether;
        assertTrue(
            sentValue < cost,
            "Test precondition failed: sentValue should be less than cost"
        );

        vm.prank(USER);

        // Log allowance before the call
        uint256 allowance = token.allowance(USER, address(spoke));
        console.log(
            "Allowance for Spoke from USER before repay call:",
            allowance
        );

        // Expect InsufficientValue
        vm.expectRevert(PeridotSpoke.InsufficientValue.selector);
        spoke.repay{value: sentValue}(address(token), TEST_AMOUNT);
    }

    // Test reverting due to zero amount
    function testRevert_ZeroAmount() public {
        vm.prank(USER);

        // Deposit
        vm.expectRevert(PeridotSpoke.InvalidAmount.selector);
        spoke.deposit{value: 0.01 ether}(address(token), 0);

        // Borrow
        vm.expectRevert(PeridotSpoke.InvalidAmount.selector);
        spoke.borrow{value: 0.01 ether}(address(token), 0);

        // Repay
        vm.expectRevert(PeridotSpoke.InvalidAmount.selector);
        spoke.repay{value: 0.01 ether}(address(token), 0);

        // Withdraw
        vm.expectRevert(PeridotSpoke.InvalidAmount.selector);
        spoke.withdraw{value: 0.01 ether}(address(token), 0);
    }

    // Test replay attack on receiveWormholeMessages
    function testRevert_ReceiveWormholeMessages_Replay() public {
        bytes memory payload = abi.encode(0, USER, address(token), TEST_AMOUNT);
        bytes[] memory additionalVaas = new bytes[](0);
        bytes32 sourceAddress = bytes32(uint256(uint160(HUB_ADDRESS)));
        uint16 sourceChain = HUB_CHAIN_ID;
        bytes32 deliveryHash = keccak256(payload);

        // 1. Process successfully
        vm.prank(address(relayer));
        spoke.receiveWormholeMessages(
            payload,
            additionalVaas,
            sourceAddress,
            sourceChain,
            deliveryHash
        );

        // Verify message is marked as processed
        assertTrue(spoke.processedMessages(deliveryHash));

        // 2. Attempt to process again (should be ignored, no revert)
        vm.prank(address(relayer));
        spoke.receiveWormholeMessages(
            payload,
            additionalVaas,
            sourceAddress,
            sourceChain,
            deliveryHash
        );
        // No state change expected, just returns early
    }
}
