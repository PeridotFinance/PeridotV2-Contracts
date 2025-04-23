// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/PeridotHub.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
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

// Mock Relayer for testing
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

// Mock TokenBridge for testing
contract MockTokenBridge {
    event TokenTransferred(address token, uint256 amount, address recipient);

    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64) {
        // Simulate token transfer behavior
        emit TokenTransferred(
            token,
            amount,
            address(uint160(uint256(recipient)))
        );
        return 1;
    }

    function completeTransfer(bytes memory vaa) external returns (bool) {
        // In a real implementation this would parse the VAA and release tokens
        return true;
    }

    function wrappedAsset(
        uint16 chainId,
        bytes32 tokenAddress
    ) external view returns (address) {
        // Return a dummy wrapped asset address
        return address(0x123);
    }
}

// Mock Wormhole for testing
contract MockWormhole {
    uint256 public currentMessageFee = 0.001 ether; // Set a default test fee

    function messageFee() external view returns (uint256) {
        return currentMessageFee;
    }

    function setMessageFee(uint256 newFee) external {
        currentMessageFee = newFee;
    }

    // VAA Header structure offsets
    uint256 internal constant VAA_HEADER_LENGTH = 1 + 4 + 4 + 2 + 32 + 8 + 1; // 52 bytes
    uint256 internal constant VAA_VERSION_OFFSET = 0;
    uint256 internal constant VAA_TIMESTAMP_OFFSET = 1;
    uint256 internal constant VAA_NONCE_OFFSET = 5;
    uint256 internal constant VAA_EMITTER_CHAIN_OFFSET = 9;
    uint256 internal constant VAA_EMITTER_ADDRESS_OFFSET = 11;
    uint256 internal constant VAA_SEQUENCE_OFFSET = 43;
    uint256 internal constant VAA_CONSISTENCY_LEVEL_OFFSET = 51;
    uint256 internal constant VAA_PAYLOAD_OFFSET = 52;

    function parseAndVerifyVM(
        bytes memory vaa
    )
        external
        pure
        returns (IWormhole.VM memory vm, bool valid, string memory reason)
    {
        // Basic mock implementation for testing token bridge VAAs
        uint256 vaaLength = vaa.length;
        if (vaaLength < VAA_HEADER_LENGTH) {
            return (vm, false, "InvalidVaaLength");
        }

        // Simulate successful parsing using assembly to read from memory
        // WARNING: Highly simplified, assumes VAA is valid and doesn't check signatures
        assembly {
            let vaaPtr := add(vaa, 0x20) // Pointer to the start of the bytes data

            // Read header fields
            vm := mload(0x40) // Allocate memory for the struct (solidity does this automatically, but helps clarity)
            mstore(
                add(vm, 0x00),
                shr(248, mload(add(vaaPtr, VAA_VERSION_OFFSET)))
            ) // version (uint8)
            mstore(
                add(vm, 0x20),
                shr(224, mload(add(vaaPtr, VAA_TIMESTAMP_OFFSET)))
            ) // timestamp (uint32)
            mstore(
                add(vm, 0x40),
                shr(224, mload(add(vaaPtr, VAA_NONCE_OFFSET)))
            ) // nonce (uint32)
            mstore(
                add(vm, 0x60),
                shr(240, mload(add(vaaPtr, VAA_EMITTER_CHAIN_OFFSET)))
            ) // emitterChainId (uint16)
            mstore(
                add(vm, 0x80),
                mload(add(vaaPtr, VAA_EMITTER_ADDRESS_OFFSET))
            ) // emitterAddress (bytes32)
            mstore(
                add(vm, 0xA0),
                shr(192, mload(add(vaaPtr, VAA_SEQUENCE_OFFSET)))
            ) // sequence (uint64)
            mstore(
                add(vm, 0xC0),
                shr(248, mload(add(vaaPtr, VAA_CONSISTENCY_LEVEL_OFFSET)))
            ) // consistencyLevel (uint8)

            // Handle payload (dynamic bytes)
            let payloadPtr := add(vm, 0xE0) // Pointer to the payload field within the VM struct
            let payloadLen := sub(vaaLength, VAA_PAYLOAD_OFFSET)
            mstore(payloadPtr, payloadLen) // Store payload length
            // Copy payload data
            let dataStart := add(vaaPtr, VAA_PAYLOAD_OFFSET)
            let dataDest := add(payloadPtr, 0x20) // Destination for payload bytes data
            calldatacopy(dataDest, dataStart, payloadLen) // Use calldatacopy as a memory copy primitive here

            // Store pointer to payload in vm struct
            mstore(add(vm, 0xE0), payloadPtr) // This line might be redundant depending on how struct memory is laid out, keeping for clarity
        }

        return (vm, true, "");
    }
}

contract PeridotHubBasicTest is Test {
    PeridotHub public hub;
    MockERC20 public token;
    MockComptroller public comptroller;
    MockRelayer public relayer;
    MockTokenBridge public tokenBridge;
    MockWormhole public mockWormhole;
    address public constant TOKEN_BRIDGE = address(0x456);
    address public owner = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        // Deploy mock contracts
        token = new MockERC20();
        comptroller = new MockComptroller();
        relayer = new MockRelayer();
        mockWormhole = new MockWormhole();

        // Deploy and store code at TOKEN_BRIDGE address using vm.etch
        tokenBridge = new MockTokenBridge();
        vm.etch(TOKEN_BRIDGE, address(tokenBridge).code);

        // Give some ETH to the contracts
        vm.deal(owner, 10 ether);

        // Deploy PeridotHub, passing the MockWormhole address
        vm.prank(owner);
        hub = new PeridotHub(
            address(mockWormhole),
            TOKEN_BRIDGE,
            address(comptroller),
            address(relayer)
        );

        // Give the hub some ETH for relayer fees and wormhole fees
        vm.deal(address(hub), 1 ether);

        // Mint some tokens to the user
        token.mint(user, 1000e18);
    }

    function test_RegisterMarket() public {
        // Create a mock cToken
        MockCToken cToken = new MockCToken(address(token));

        // Register the market
        vm.prank(owner);
        hub.registerMarket(address(token), address(cToken));

        // Verify the market was registered
        assertEq(hub.underlyingToPToken(address(token)), address(cToken));
        assertTrue(hub.registeredMarkets(address(cToken)));
    }

    function test_RegisterMarket_NotOwner() public {
        // Create a mock cToken
        MockCToken cToken = new MockCToken(address(token));

        // Try to register market as non-owner
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        hub.registerMarket(address(token), address(cToken));
    }

    function test_RegisterMarket_InvalidAddresses() public {
        // Try to register with zero addresses
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PeridotHub.InvalidAddress.selector, "market")
        );
        hub.registerMarket(address(0), address(0));
    }

    function test_RegisterMarket_AlreadyRegistered() public {
        // Create mock cTokens
        MockCToken cToken1 = new MockCToken(address(token));
        MockCToken cToken2 = new MockCToken(address(token));

        // Register first market
        vm.prank(owner);
        hub.registerMarket(address(token), address(cToken1));

        // Try to register the same cToken again
        vm.prank(owner);
        vm.expectRevert(PeridotHub.MarketNotSupported.selector);
        hub.registerMarket(address(token), address(cToken1));

        // NOTE: The current contract implementation only checks if cToken is already registered,
        // but doesn't prevent registering a new cToken for an existing underlying.
        // This means the mapping will be overwritten.

        // Register a different cToken for the same underlying (should succeed)
        vm.prank(owner);
        hub.registerMarket(address(token), address(cToken2));

        // Verify the mapping was updated
        assertEq(hub.underlyingToPToken(address(token)), address(cToken2));
        assertTrue(hub.registeredMarkets(address(cToken2)));
    }

    function test_SetTrustedEmitter() public {
        uint16 testChainId = 10;
        bytes32 testEmitter = bytes32(uint256(uint160(address(0xABC))));

        // Initial state
        assertFalse(hub.trustedEmitters(testChainId, testEmitter));

        // Set emitter as owner
        vm.prank(owner);
        hub.setTrustedEmitter(testChainId, testEmitter, true);
        assertTrue(hub.trustedEmitters(testChainId, testEmitter));

        // Unset emitter as owner
        vm.prank(owner);
        hub.setTrustedEmitter(testChainId, testEmitter, false);
        assertFalse(hub.trustedEmitters(testChainId, testEmitter));
    }

    function test_SetTrustedEmitter_NotOwner() public {
        uint16 testChainId = 10;
        bytes32 testEmitter = bytes32(uint256(uint160(address(0xABC))));

        // Try to set emitter as non-owner
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        hub.setTrustedEmitter(testChainId, testEmitter, true);
    }

    function test_EmergencyWithdraw() public {
        uint256 amountToWithdraw = 500e18;

        // Mint tokens directly to the hub contract
        token.mint(address(hub), amountToWithdraw);
        assertEq(token.balanceOf(address(hub)), amountToWithdraw);
        assertEq(token.balanceOf(owner), 0);

        // Withdraw as owner
        vm.prank(owner);
        hub.emergencyWithdraw(address(token));

        // Verify tokens are transferred to owner
        assertEq(token.balanceOf(address(hub)), 0);
        assertEq(token.balanceOf(owner), amountToWithdraw);
    }

    function test_EmergencyWithdraw_NotOwner() public {
        uint256 amountToWithdraw = 500e18;
        token.mint(address(hub), amountToWithdraw);

        // Try to withdraw as non-owner
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        hub.emergencyWithdraw(address(token));
    }

    function test_EmergencyWithdraw_ZeroBalance() public {
        assertEq(token.balanceOf(address(hub)), 0);
        assertEq(token.balanceOf(owner), 0);

        // Withdraw with zero balance (should succeed but do nothing)
        vm.prank(owner);
        hub.emergencyWithdraw(address(token));

        assertEq(token.balanceOf(address(hub)), 0);
        assertEq(token.balanceOf(owner), 0);
    }

    function test_Constructor_InvalidAddresses() public {
        // Test invalid wormhole address
        vm.expectRevert(
            abi.encodeWithSelector(
                PeridotHub.InvalidAddress.selector,
                "wormhole"
            )
        );
        new PeridotHub(
            address(0),
            TOKEN_BRIDGE,
            address(comptroller),
            address(relayer)
        );

        // Test invalid token bridge address
        vm.expectRevert(
            abi.encodeWithSelector(
                PeridotHub.InvalidAddress.selector,
                "token bridge"
            )
        );
        new PeridotHub(
            address(mockWormhole),
            address(0),
            address(comptroller),
            address(relayer)
        );

        // Test invalid comptroller address
        vm.expectRevert(
            abi.encodeWithSelector(
                PeridotHub.InvalidAddress.selector,
                "peridottroller"
            )
        );
        new PeridotHub(
            address(mockWormhole),
            TOKEN_BRIDGE,
            address(0),
            address(relayer)
        );

        // Test invalid relayer address
        vm.expectRevert(
            abi.encodeWithSelector(
                PeridotHub.InvalidAddress.selector,
                "relayer"
            )
        );
        new PeridotHub(
            address(mockWormhole),
            TOKEN_BRIDGE,
            address(comptroller),
            address(0)
        );
    }

    function test_ReceiveEther() public {
        // Initial balance
        uint256 initialBalance = address(hub).balance;

        // Send ether to hub
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success, ) = address(hub).call{value: 0.5 ether}("");

        // Verify success and balance increase
        assertTrue(success);
        assertEq(address(hub).balance, initialBalance + 0.5 ether);
    }

    function test_SendTokensToUser() public {
        // Set up the test by registering a market
        MockCToken cToken = new MockCToken(address(token));
        vm.prank(owner);
        hub.registerMarket(address(token), address(cToken));

        // Transfer tokens to the hub
        token.mint(address(hub), 100e18);

        // Create and register a trusted emitter
        bytes32 emitterAddress = bytes32(uint256(uint160(user)));
        uint16 chainId = 1;

        vm.prank(owner);
        hub.setTrustedEmitter(chainId, emitterAddress, true);

        // Create a borrow request payload
        bytes memory payload = abi.encode(
            uint8(2), // PAYLOAD_ID_BORROW
            user,
            address(token),
            50e18
        );

        // Process the borrow request
        vm.prank(address(relayer));
        hub.receiveWormholeMessages(
            payload,
            new bytes[](0),
            emitterAddress,
            chainId,
            keccak256(payload)
        );

        // Verify that a message was sent back via the relayer
        assertEq(relayer.getMessageCount(), 1);
        MockRelayer.RelayerMessage memory message = relayer.getLastMessage();

        // Decode the payload
        (
            uint8 status,
            address recipient,
            address tokenAddr,
            uint256 amount
        ) = abi.decode(message.payload, (uint8, address, address, uint256));

        // Verify the message contents
        assertEq(status, 0, "Status should be success");
        assertEq(recipient, user, "Recipient should be the user");
        assertEq(tokenAddr, address(token), "Token should match");
        assertEq(amount, 50e18, "Amount should match the borrowed amount");
    }

    // Test that verifies our mock token bridge is properly set up
    function test_MockTokenBridgeSetup() public {
        // Get the bytecode at the TOKEN_BRIDGE address
        uint256 codeSize;
        address addr = TOKEN_BRIDGE;

        assembly {
            codeSize := extcodesize(addr)
        }

        // Verify that there is code at the TOKEN_BRIDGE address
        assertTrue(codeSize > 0, "No code at TOKEN_BRIDGE address");

        // Test calling the transferTokens function
        MockTokenBridge bridge = MockTokenBridge(TOKEN_BRIDGE);
        uint64 result = bridge.transferTokens(
            address(token),
            100,
            1,
            bytes32(uint256(uint160(address(this)))),
            0,
            0
        );

        // Verify the result
        assertEq(result, 1, "TokenBridge did not return expected result");
    }
}
