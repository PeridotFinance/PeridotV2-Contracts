// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "../lib/forge-std/src/Test.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

// Simple interfaces for our mocks
interface CToken {
    function symbol() external view returns (string memory);
}

interface CErc20 is CToken {
    function underlying() external view returns (address);
}

interface PriceOracle {
    function getUnderlyingPrice(CToken cToken) external view returns (uint);
}

// Mock implementations
contract MockCErc20 is CErc20 {
    string private _symbol;
    address private _underlying;

    constructor(string memory symbol_, address underlying_) {
        _symbol = symbol_;
        _underlying = underlying_;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function underlying() external view override returns (address) {
        return _underlying;
    }
}

contract MockCToken is CToken {
    string private _symbol;

    constructor(string memory symbol_) {
        _symbol = symbol_;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }
}

// Simplified MockSimplePriceOracle that mimics the behavior we expect
contract MockSimplePriceOracle {
    MockPyth public pyth;
    uint public pythPriceStaleThreshold;
    mapping(address => uint) public prices;
    mapping(address => bool) public admin;
    mapping(address => bytes32) public assetToPythId;

    event PricePosted(
        address asset,
        uint previousPriceMantissa,
        uint requestedPriceMantissa,
        uint newPriceMantissa
    );
    event PythFeedRegistered(address asset, bytes32 priceId);

    constructor(address _pythContract, uint _staleThreshold) {
        pyth = MockPyth(_pythContract);
        pythPriceStaleThreshold = _staleThreshold;
        admin[msg.sender] = true;
    }

    function _getUnderlyingAddress(
        CToken cToken
    ) private view returns (address) {
        address asset;
        if (
            keccak256(abi.encodePacked(cToken.symbol())) ==
            keccak256(abi.encodePacked("cETH"))
        ) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = CErc20(address(cToken)).underlying();
        }
        return asset;
    }

    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        address asset = _getUnderlyingAddress(cToken);
        bytes32 priceId = assetToPythId[asset];

        if (priceId != bytes32(0)) {
            try
                pyth.getPriceNoOlderThan(priceId, pythPriceStaleThreshold)
            returns (PythStructs.Price memory price) {
                // Convert price to 18 decimals
                uint priceMantissa = uint(uint64(price.price));
                int32 expo = price.expo;

                // Safe conversion of negative expo to positive decimal places
                uint priceDecimals;
                if (expo < 0) {
                    priceDecimals = uint(int(-expo));
                } else {
                    priceDecimals = 0;
                }

                // Scale to 18 decimals
                if (priceDecimals < 18) {
                    priceMantissa =
                        priceMantissa *
                        (10 ** (18 - priceDecimals));
                } else if (priceDecimals > 18) {
                    priceMantissa =
                        priceMantissa /
                        (10 ** (priceDecimals - 18));
                }

                return priceMantissa;
            } catch {
                return prices[asset];
            }
        }

        return prices[asset];
    }

    function setUnderlyingPrice(
        CToken cToken,
        uint underlyingPriceMantissa
    ) public {
        require(admin[msg.sender], "Only admin can call this function");
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public {
        require(admin[msg.sender], "Only admin can call this function");
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    function registerPythFeed(address asset, bytes32 priceId) public {
        require(admin[msg.sender], "Only admin can call this function");
        assetToPythId[asset] = priceId;
        emit PythFeedRegistered(asset, priceId);
    }

    function updatePythPrices(bytes[] calldata priceUpdateData) public payable {
        uint fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee for Pyth update");

        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function setPythStaleThreshold(uint _newThreshold) public {
        require(admin[msg.sender], "Only admin can call this function");
        pythPriceStaleThreshold = _newThreshold;
    }

    function setAdmin(address _newAdmin) public {
        require(admin[msg.sender], "Only admin can call this function");
        admin[_newAdmin] = true;
    }

    function assetPrices(address asset) external view returns (uint) {
        bytes32 priceId = assetToPythId[asset];

        if (priceId != bytes32(0)) {
            try
                pyth.getPriceNoOlderThan(priceId, pythPriceStaleThreshold)
            returns (PythStructs.Price memory price) {
                // Convert price to 18 decimals
                uint priceMantissa = uint(uint64(price.price));
                int32 expo = price.expo;

                // Safe conversion of negative expo to positive decimal places
                uint priceDecimals;
                if (expo < 0) {
                    priceDecimals = uint(int(-expo));
                } else {
                    priceDecimals = 0;
                }

                // Scale to 18 decimals
                if (priceDecimals < 18) {
                    priceMantissa =
                        priceMantissa *
                        (10 ** (18 - priceDecimals));
                } else if (priceDecimals > 18) {
                    priceMantissa =
                        priceMantissa /
                        (10 ** (priceDecimals - 18));
                }

                return priceMantissa;
            } catch {
                return prices[asset];
            }
        }

        return prices[asset];
    }
}

contract SimplePriceOracleTest is Test {
    MockPyth public pyth;
    MockSimplePriceOracle public priceOracle;

    // Price feed IDs
    bytes32 constant ETH_USD_PRICE_ID = bytes32(uint256(0x1));
    bytes32 constant BTC_USD_PRICE_ID = bytes32(uint256(0x2));
    bytes32 constant USDC_USD_PRICE_ID = bytes32(uint256(0x3));

    // Mock tokens
    address constant WETH = address(0x1);
    address constant WBTC = address(0x2);
    address constant USDC = address(0x3);

    // Mock cTokens
    MockCToken cETH;
    MockCErc20 cWBTC;
    MockCErc20 cUSDC;

    // Stale threshold in seconds
    uint constant PRICE_STALE_THRESHOLD = 60;

    function setUp() public {
        // Initialize MockPyth
        pyth = new MockPyth(PRICE_STALE_THRESHOLD, 1);

        // Initialize our mock price oracle
        priceOracle = new MockSimplePriceOracle(
            address(pyth),
            PRICE_STALE_THRESHOLD
        );

        // Initialize mock tokens and cTokens
        cETH = new MockCToken("cETH");
        cWBTC = new MockCErc20("cWBTC", WBTC);
        cUSDC = new MockCErc20("cUSDC", USDC);

        // Register price feeds
        priceOracle.registerPythFeed(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            ETH_USD_PRICE_ID
        ); // ETH
        priceOracle.registerPythFeed(WBTC, BTC_USD_PRICE_ID);
        priceOracle.registerPythFeed(USDC, USDC_USD_PRICE_ID);
    }

    // Helper to create price updates
    function createPriceUpdate(
        bytes32 priceId,
        int64 price,
        int32 expo
    ) internal view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = pyth.createPriceFeedUpdateData(
            priceId,
            price,
            10,
            expo,
            price,
            10,
            uint64(block.timestamp),
            uint64(block.timestamp)
        );

        return updateData;
    }

    // Helper to update price
    function updatePrice(bytes32 priceId, int64 price, int32 expo) internal {
        bytes[] memory updateData = createPriceUpdate(priceId, price, expo);
        uint fee = pyth.getUpdateFee(updateData);
        vm.deal(address(this), fee);
        pyth.updatePriceFeeds{value: fee}(updateData);
    }

    // Test basic price fetching
    function testGetPriceFromPyth() public {
        // Set ETH price to 2000 USD with -8 exponent
        updatePrice(ETH_USD_PRICE_ID, 200000000000, -8);

        // Get price from oracle
        uint price = priceOracle.getUnderlyingPrice(cETH);

        // Price should be scaled to 18 decimals
        assertEq(price, 2000 * 10 ** 18);
    }

    // Test updating price through oracle
    function testUpdatePythPrice() public {
        // Create price update for BTC at 40000 USD
        bytes[] memory updateData = createPriceUpdate(
            BTC_USD_PRICE_ID,
            4000000000000,
            -8
        );

        // Get fee and update through oracle
        uint fee = pyth.getUpdateFee(updateData);
        vm.deal(address(this), fee);
        priceOracle.updatePythPrices{value: fee}(updateData);

        // Check price
        uint price = priceOracle.getUnderlyingPrice(cWBTC);
        assertEq(price, 40000 * 10 ** 18);
    }

    // Test fallback to manual price
    function testFallbackToManualPrice() public {
        // Set ETH price
        updatePrice(ETH_USD_PRICE_ID, 200000000000, -8);

        // Skip time to make price stale
        skip(PRICE_STALE_THRESHOLD + 10);

        // Set manual price
        priceOracle.setDirectPrice(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            1900 * 10 ** 18
        );

        // Get price - should use manual price since Pyth is stale
        uint price = priceOracle.getUnderlyingPrice(cETH);
        assertEq(price, 1900 * 10 ** 18);
    }

    // Test with different exponents
    function testDifferentExponents() public {
        // USDC price with -6 exponent
        updatePrice(USDC_USD_PRICE_ID, 1000000, -6);

        uint price = priceOracle.getUnderlyingPrice(cUSDC);
        assertEq(price, 1 * 10 ** 18);

        // USDC price with -10 exponent
        updatePrice(USDC_USD_PRICE_ID, 10000000000, -10);

        price = priceOracle.getUnderlyingPrice(cUSDC);
        assertEq(price, 1 * 10 ** 18);
    }

    // Make contract payable
    receive() external payable {}
}
