// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "./CToken.sol";
import "./CErc20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISupraOraclePull {
    struct PriceData {
        uint256[] pairs;
        uint256[] prices;
        uint256[] decimals;
    }

    struct PriceInfo {
        uint256[] pairs;
        uint256[] prices;
        uint256[] timestamps;
        uint256[] decimals;
        uint256[] rounds;
    }

    function verifyOracleProof(
        bytes calldata _bytesProof
    ) external returns (PriceData memory);
}

contract SupraPriceOracle is PriceOracle, Ownable {
    // Mapping from asset to price (scaled by 1e18)
    mapping(address => uint256) public prices;

    // Mapping from asset to Supra pair ID
    mapping(address => uint256) public assetPairIds;

    // Mapping from pair ID to asset
    mapping(uint256 => address) public pairIdToAsset;

    // Supra Oracle Pull contract instance
    ISupraOraclePull public supraOraclePull;

    // Events
    event PriceUpdated(address indexed asset, uint256 price);
    event SupraOraclePullAddressUpdated(address indexed newAddress);
    event AssetPairIdSet(address indexed asset, uint256 pairId);
    event PairIdToAssetSet(uint256 indexed pairId, address asset);

    constructor(address _supraOraclePull) Ownable(msg.sender) {
        require(
            _supraOraclePull != address(0),
            "Invalid Supra Oracle Pull address"
        );
        supraOraclePull = ISupraOraclePull(_supraOraclePull);
    }

    // Function to set the pair ID for an asset
    function setAssetPairId(address asset, uint256 pairId) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        assetPairIds[asset] = pairId;
        emit AssetPairIdSet(asset, pairId);
    }

    // Function to set the asset for a pair ID
    function setPairIdToAsset(
        uint256 pairId,
        address asset
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        pairIdToAsset[pairId] = asset;
        emit PairIdToAssetSet(pairId, asset);
    }

    // Function to update prices by verifying the proof
    function updatePrices(bytes calldata _bytesProof) external onlyOwner {
        ISupraOraclePull.PriceData memory priceData = supraOraclePull
            .verifyOracleProof(_bytesProof);

        for (uint256 i = 0; i < priceData.pairs.length; i++) {
            uint256 pairId = priceData.pairs[i];
            uint256 price = priceData.prices[i];
            uint256 decimals = priceData.decimals[i];

            // Find the asset corresponding to the pairId
            address asset = getAssetByPairId(pairId);
            require(asset != address(0), "Asset not found for pair ID");

            // Adjust the price to 18 decimals
            uint256 adjustedPrice = adjustPriceDecimals(price, decimals);

            // Store the price
            prices[asset] = adjustedPrice;

            emit PriceUpdated(asset, adjustedPrice);
        }
    }

    // Function to adjust price decimals to 18 decimals
    function adjustPriceDecimals(
        uint256 price,
        uint256 priceDecimals
    ) internal pure returns (uint256) {
        if (priceDecimals < 18) {
            return price * (10 ** (18 - priceDecimals));
        } else if (priceDecimals > 18) {
            return price / (10 ** (priceDecimals - 18));
        } else {
            return price;
        }
    }

    // Function to get asset by pair ID
    function getAssetByPairId(uint256 pairId) internal view returns (address) {
        return pairIdToAsset[pairId];
    }

    // Implement the getUnderlyingPrice function
    function getUnderlyingPrice(
        CToken cToken
    ) public view override returns (uint256) {
        address asset = _getUnderlyingAddress(cToken);
        uint256 price = prices[asset];
        require(price > 0, "Price not available");
        return price;
    }

    // Helper function to get the underlying asset address
    function _getUnderlyingAddress(
        CToken cToken
    ) internal view returns (address) {
        if (compareStrings(cToken.symbol(), "cETH")) {
            return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Address representation for ETH
        } else {
            return address(CErc20(address(cToken)).underlying());
        }
    }

    // Function to compare strings
    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // Function to update the Supra Oracle Pull contract address
    function setSupraOraclePullAddress(
        address _supraOraclePull
    ) external onlyOwner {
        require(_supraOraclePull != address(0), "Invalid address");
        supraOraclePull = ISupraOraclePull(_supraOraclePull);
        emit SupraOraclePullAddressUpdated(_supraOraclePull);
    }
}
