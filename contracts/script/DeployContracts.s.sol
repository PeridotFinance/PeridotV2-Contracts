// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/MockERc20.sol";
import "../contracts/SimplePriceOracle.sol";

/**
 * @title DeployContracts
 * @dev A forge script to deploy MockERC20 token and SimplePriceOracle
 * Usage: forge script script/DeployContracts.s.sol:DeployContracts --rpc-url $ARBITRUM_SEPOLIA_URL --private-key $PRIVATE_KEY_TEST --broadcast
 */
contract DeployContracts is Script {
    // Network-specific Pyth contract addresses
    address constant PYTH_MAINNET = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // Arbitrum Sepolia
    address constant PYTH_GOERLI = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Goerli Testnet
    address constant PYTH_SEPOLIA = 0x2880aB155794e7179c9eE2e38200202908C17B43; // Sepolia Testnet
    address constant PYTH_OPTIMISM = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Optimism Mainnet
    address constant PYTH_OP_SEPOLIA =
        0x0708325268dF9F66270F1401206434524814508b; // Optimism Sepolia Testnet

    // Common price feed IDs
    bytes32 constant ETH_USD_PRICE_ID =
        0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant BTC_USD_PRICE_ID =
        0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    bytes32 constant USDC_USD_PRICE_ID =
        0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    // Price staleness threshold (in seconds)
    uint constant PRICE_STALE_THRESHOLD = 60; // 60 seconds

    function run() public {
        // Determine which network we're deploying to by checking the chain ID
        address pythAddress;
        uint chainId = block.chainid;

        if (chainId == 421614) {
            pythAddress = PYTH_MAINNET; // Ethereum Mainnet
        } else if (chainId == 5) {
            pythAddress = PYTH_GOERLI; // Goerli Testnet
        } else if (chainId == 11155111) {
            pythAddress = PYTH_SEPOLIA; // Sepolia Testnet
        } else if (chainId == 10) {
            pythAddress = PYTH_OPTIMISM; // Optimism Mainnet
        } else if (chainId == 11155420) {
            pythAddress = PYTH_OP_SEPOLIA; // Optimism Sepolia Testnet
        } else {
            // Default to Sepolia if chain ID is unknown
            console.log(
                "Unknown chain ID: %s. Defaulting to Arbitrum Sepolia",
                chainId
            );
            pythAddress = PYTH_MAINNET;
        }

        console.log("Deploying to chain ID: %s", chainId);
        console.log("Using Pyth address: %s", pythAddress);

        vm.startBroadcast();

        // Step 1: Deploy the MyToken contract (MockERC20)
        MyToken myToken = new MyToken(msg.sender);
        console.log("MyToken deployed at: %s", address(myToken));

        // Step 2: Deploy the SimplePriceOracle
        SimplePriceOracle priceOracle = new SimplePriceOracle(
            pythAddress,
            PRICE_STALE_THRESHOLD
        );
        console.log("SimplePriceOracle deployed at: %s", address(priceOracle));

        // Step 3: For testing, mint some tokens to the deployer
        myToken.mint(msg.sender, 1000000 * (10 ** 18)); // Mint 1,000,000 tokens
        console.log("Minted 1,000,000 tokens to: %s", msg.sender);

        // Step 4: Register the token with a test price feed ID in the oracle
        // For testing purposes, we'll use the USDC price feed ID for our token
        priceOracle.registerPythFeed(address(myToken), USDC_USD_PRICE_ID);
        console.log("Registered MyToken with USDC price feed ID");

        // Step 5: Also register ETH and BTC price feeds for testing
        priceOracle.registerPythFeed(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            ETH_USD_PRICE_ID
        );
        console.log("Registered ETH price feed");

        vm.stopBroadcast();

        // Output deployment summary
        console.log("\n==== Deployment Summary ====");
        console.log("MyToken (MTK): %s", address(myToken));
        console.log("SimplePriceOracle: %s", address(priceOracle));
        console.log("Pyth Contract: %s", pythAddress);
        console.log("Price Stale Threshold: %s seconds", PRICE_STALE_THRESHOLD);
    }
}
