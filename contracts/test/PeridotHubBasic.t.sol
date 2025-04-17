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
    ) external returns (uint64) {
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

contract PeridotHubBasicTest is Test {
    PeridotHub public hub;
    MockERC20 public token;
    MockComptroller public comptroller;
    MockRelayer public relayer;
    MockTokenBridge public tokenBridge;
    address public constant WORMHOLE = address(0x123);
    address public constant TOKEN_BRIDGE = address(0x456);
    address public owner = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        // Deploy mock contracts
        token = new MockERC20();
        comptroller = new MockComptroller();
        relayer = new MockRelayer();

        // Deploy and store code at TOKEN_BRIDGE address using vm.etch
        tokenBridge = new MockTokenBridge();
        vm.etch(TOKEN_BRIDGE, address(tokenBridge).code);

        // Give some ETH to the contracts
        vm.deal(owner, 10 ether);

        // Deploy PeridotHub
        vm.prank(owner);
        hub = new PeridotHub(
            WORMHOLE,
            TOKEN_BRIDGE,
            address(comptroller),
            address(relayer)
        );

        // Give the hub some ETH for relayer fees
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
        bytes32 emitterAddress = bytes32(uint256(0x123));
        uint16 chainId = 1;

        // Set trusted emitter
        vm.prank(owner);
        hub.setTrustedEmitter(chainId, emitterAddress, true);

        // Verify the emitter was registered
        assertTrue(hub.trustedEmitters(chainId, emitterAddress));
    }

    function test_SetTrustedEmitter_NotOwner() public {
        bytes32 emitterAddress = bytes32(uint256(0x123));
        uint16 chainId = 1;

        // Try to set trusted emitter as non-owner
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        hub.setTrustedEmitter(chainId, emitterAddress, true);
    }

    function test_EmergencyWithdraw() public {
        // Create a mock cToken and register market
        MockCToken cToken = new MockCToken(address(token));
        vm.prank(owner);
        hub.registerMarket(address(token), address(cToken));

        // Transfer some tokens to the hub
        vm.prank(user);
        token.transfer(address(hub), 100e18);

        // Perform emergency withdraw
        vm.prank(owner);
        hub.emergencyWithdraw(address(token));

        // Verify tokens were transferred to owner
        assertEq(token.balanceOf(owner), 100e18);
        assertEq(token.balanceOf(address(hub)), 0);
    }

    function test_EmergencyWithdraw_NotOwner() public {
        // Try to perform emergency withdraw as non-owner
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        hub.emergencyWithdraw(address(token));
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
            WORMHOLE,
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
        new PeridotHub(WORMHOLE, TOKEN_BRIDGE, address(0), address(relayer));

        // Test invalid relayer address
        vm.expectRevert(
            abi.encodeWithSelector(
                PeridotHub.InvalidAddress.selector,
                "relayer"
            )
        );
        new PeridotHub(
            WORMHOLE,
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
