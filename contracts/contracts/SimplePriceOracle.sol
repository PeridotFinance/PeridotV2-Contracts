// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "./PErc20.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint) prices;
    mapping(address => bool) public admin;
    mapping(address => bytes32) public assetToPythId; // Maps asset addresses to Pyth price feed IDs
    mapping(bytes32 => uint) public lastValidPythPriceMantissa; // Stores the last valid price mantissa from Pyth
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
    event LastPythPriceUpdated(bytes32 indexed priceId, uint priceMantissa); // Event for last valid price update

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
        PToken pToken
    ) private view returns (address) {
        address asset;
        if (peridotareStrings(pToken.symbol(), "cETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(PErc20(address(pToken)).underlying());
        }
        return asset;
    }

    function getUnderlyingPrice(
        PToken pToken
    ) public view override returns (uint) {
        address asset = _getUnderlyingAddress(pToken);
        bytes32 priceId = assetToPythId[asset];

        if (priceId != bytes32(0)) {
            try pyth.getPriceUnsafe(priceId) returns (
                PythStructs.Price memory price
            ) {
                // Check if the price timestamp is within the allowed threshold
                if (
                    block.timestamp - price.publishTime <=
                    pythPriceStaleThreshold
                ) {
                    // Price is fresh, convert and return
                    uint priceDecimals;
                    if (price.expo < 0) {
                        priceDecimals = uint(-int(price.expo));
                    } else {
                        priceDecimals = 0;
                    }
                    uint priceMantissa = uint(uint64(price.price));
                    if (priceDecimals < 18) {
                        priceMantissa =
                            priceMantissa *
                            (10 ** (18 - priceDecimals));
                    } else if (priceDecimals > 18) {
                        priceMantissa =
                            priceMantissa /
                            (10 ** (priceDecimals - 18));
                    }
                    // NOTE: We cannot update lastValidPythPriceMantissa here as it's a view function
                    return priceMantissa;
                } else {
                    // Price is stale, return last known valid price if available
                    uint lastValidPrice = lastValidPythPriceMantissa[priceId];
                    if (lastValidPrice != 0) {
                        return lastValidPrice;
                    }
                    // If no last valid price, fall through to manual price
                }
            } catch {
                // If getPriceUnsafe fails, try returning last known valid price
                uint lastValidPrice = lastValidPythPriceMantissa[priceId];
                if (lastValidPrice != 0) {
                    return lastValidPrice;
                }
                // If that fails too, fall through to manual price
            }
        }

        // Fallback to manually set price
        return prices[asset];
    }

    function setUnderlyingPrice(
        PToken pToken,
        uint underlyingPriceMantissa
    ) public onlyAdmin {
        address asset = _getUnderlyingAddress(pToken);
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
            try pyth.getPriceUnsafe(priceId) returns (
                PythStructs.Price memory price
            ) {
                // Check if the price timestamp is within the allowed threshold
                if (
                    block.timestamp - price.publishTime <=
                    pythPriceStaleThreshold
                ) {
                    // Price is fresh, convert and return
                    uint priceDecimals;
                    if (price.expo < 0) {
                        priceDecimals = uint(-int(price.expo));
                    } else {
                        priceDecimals = 0;
                    }
                    uint priceMantissa = uint(uint64(price.price));
                    if (priceDecimals < 18) {
                        priceMantissa =
                            priceMantissa *
                            (10 ** (18 - priceDecimals));
                    } else if (priceDecimals > 18) {
                        priceMantissa =
                            priceMantissa /
                            (10 ** (priceDecimals - 18));
                    }
                    // NOTE: Cannot update cache here
                    return priceMantissa;
                } else {
                    // Price is stale, return last known valid price if available
                    uint lastValidPrice = lastValidPythPriceMantissa[priceId];
                    if (lastValidPrice != 0) {
                        return lastValidPrice;
                    }
                    // If no last valid price, fall through to manual price
                }
            } catch {
                // If getPriceUnsafe fails, try returning last known valid price
                uint lastValidPrice = lastValidPythPriceMantissa[priceId];
                if (lastValidPrice != 0) {
                    return lastValidPrice;
                }
                // If that fails too, fall through to manual price
            }
        }
        // Fallback to manually set price
        return prices[asset];
    }

    function peridotareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
