// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "./CErc20.sol";
import "node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint) prices;
    mapping(address => bool) public admin;
    mapping(address => bytes32) public assetToPythId; // Maps asset addresses to Pyth price feed IDs
    address private owner;
    IPyth public pyth; // Pyth Oracle contract instance
    uint public pythPriceStaleThreshold; // Maximum age of price feed in seconds

    event PricePosted(
        address asset,
        uint previousPriceMantissa,
        uint requestedPriceMantissa,
        uint newPriceMantissa
    );
    event PythFeedRegistered(address asset, bytes32 priceId);

    modifier onlyAdmin() {
        require(admin[msg.sender], "Only admin can call this function");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor(address _pythContract, uint _staleThreshold) {
        owner = msg.sender;
        admin[msg.sender] = true;
        pyth = IPyth(_pythContract);
        pythPriceStaleThreshold = _staleThreshold;
    }

    function _getUnderlyingAddress(
        CToken cToken
    ) private view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), "cETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }

    function getUnderlyingPrice(
        CToken cToken
    ) public view override onlyAdmin returns (uint) {
        address asset = _getUnderlyingAddress(cToken);

        // Check if we have a Pyth price feed ID for this asset
        bytes32 priceId = assetToPythId[asset];

        if (priceId != bytes32(0)) {
            try
                pyth.getPriceNoOlderThan(priceId, pythPriceStaleThreshold)
            returns (PythStructs.Price memory price) {
                // Convert Pyth price to the expected format (scaled to 18 decimals)
                // Fix the int32 to uint conversion issue
                uint priceDecimals;
                if (price.expo < 0) {
                    // Convert negative exponent to positive decimal places
                    priceDecimals = uint(-int(price.expo));
                } else {
                    // Handle positive exponent (rare but possible)
                    priceDecimals = 0;
                }

                uint priceMantissa = uint(uint64(price.price));

                // Convert to 18 decimals (which is what Compound expects)
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
                // If there's an error with Pyth (e.g., price is too old),
                // fall back to the stored price
                return prices[asset];
            }
        }

        return prices[asset];
    }

    function setUnderlyingPrice(
        CToken cToken,
        uint underlyingPriceMantissa
    ) public onlyAdmin {
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public onlyAdmin {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // Register a Pyth price feed for an asset
    function registerPythFeed(address asset, bytes32 priceId) public onlyAdmin {
        assetToPythId[asset] = priceId;
        emit PythFeedRegistered(asset, priceId);
    }

    // Update prices from Pyth Oracle
    function updatePythPrices(bytes[] calldata priceUpdateData) public payable {
        uint fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee for Pyth update");

        // Update the price feeds in Pyth contract
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        // If there's any excess ETH, return it to the sender
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    // Set the maximum age for Pyth price feeds
    function setPythStaleThreshold(uint _newThreshold) public onlyOwner {
        pythPriceStaleThreshold = _newThreshold;
    }

    function setAdmin(address _newAdmin) public onlyOwner {
        admin[_newAdmin] = true;
    }

    function removeAdmin(address _admin) public onlyOwner {
        admin[_admin] = false;
    }

    function setOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        // Check if we have a Pyth price feed ID for this asset
        bytes32 priceId = assetToPythId[asset];

        if (priceId != bytes32(0)) {
            try
                pyth.getPriceNoOlderThan(priceId, pythPriceStaleThreshold)
            returns (PythStructs.Price memory price) {
                // Convert Pyth price to the expected format (scaled to 18 decimals)
                // Fix the int32 to uint conversion issue
                uint priceDecimals;
                if (price.expo < 0) {
                    // Convert negative exponent to positive decimal places
                    priceDecimals = uint(-int(price.expo));
                } else {
                    // Handle positive exponent (rare but possible)
                    priceDecimals = 0;
                }

                uint priceMantissa = uint(uint64(price.price));

                // Convert to 18 decimals
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
                // If there's an error with Pyth, fall back to the stored price
                return prices[asset];
            }
        }

        return prices[asset];
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
