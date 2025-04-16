// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/MockERc20.sol";
import "../contracts/SimplePriceOracle.sol";

/**
 * @title UpdatePrices
 * @dev A forge script to update prices using the SimplePriceOracle
 * Usage:
 * 1. First get the price update data from Hermes:
 *    curl -s "https://hermes.pyth.network/v2/updates/price/latest?ids[]=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace" | jq -r ".binary.data[0]" > price_update.txt
 * 2. Then run the script:
 *    forge script script/DeployContracts.s.sol:UpdatePrices --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract UpdatePrices is Script {
    function run() public {
        // The address of the deployed SimplePriceOracle
        address oracleAddress = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // TODO: Replace with your deployed oracle address

        // Load price update data from file
        string memory priceUpdateHex = vm.readLine("price_update.txt");
        bytes memory priceUpdateData = vm.parseBytes(priceUpdateHex);

        bytes[] memory updates = new bytes[](1);
        updates[0] = priceUpdateData;

        console.log(
            "Updating prices with data of length: %s",
            priceUpdateData.length
        );

        vm.startBroadcast();

        // Get the fee required for the update
        uint fee = SimplePriceOracle(oracleAddress).pyth().getUpdateFee(
            updates
        );
        console.log("Update fee: %s wei", fee);

        // Update the prices
        SimplePriceOracle(oracleAddress).updatePythPrices{value: fee}(updates);
        console.log("Prices updated successfully");

        vm.stopBroadcast();
    }
}

/**
 * @title FetchPrice
 * @dev A forge script to fetch a price from the SimplePriceOracle
 * Usage: forge script script/DeployContracts.s.sol:FetchPrice --rpc-url $RPC_URL
 */
contract FetchPrice is Script {
    function run() public view {
        // The address of the deployed SimplePriceOracle
        address oracleAddress = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // TODO: Replace with your deployed oracle address

        // The address of the token to get the price for
        address tokenAddress = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // TODO: Replace with your token address

        // Get the price
        SimplePriceOracle oracle = SimplePriceOracle(oracleAddress);
        uint price = oracle.assetPrices(tokenAddress);

        console.log("Price of token %s: %s", tokenAddress, price);
        console.log("(in 18 decimal format)");

        // Convert to a more readable format (assuming 18 decimals)
        uint priceInUSD = price / 10 ** 18;
        uint decimalPart = (price % 10 ** 18) / 10 ** 14; // Get 4 decimal places

        console.log("Price in USD: %s.%s", priceInUSD, decimalPart);
    }
}
