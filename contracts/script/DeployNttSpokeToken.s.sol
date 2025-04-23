// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../contracts/NTTSpokeToken.sol";

/**
 * @title DeployNttSpokeToken
 * @notice Deploys the MyNttSpokeToken contract.
 * @dev Sets the initial admin/minter and token details from environment variables.
 */
contract DeployNTTToken is Script {
    function run() external returns (NTTToken token) {
        // --- Configuration --- //

        // !!! IMPORTANT: Token details
        string memory tokenName = "USD Tether";
        string memory tokenSymbol = "USDT";

        // Deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // --- Input Validation --- //

        bytes memory tokenNameBytes = bytes(tokenName);
        require(
            tokenNameBytes.length > 0,
            "DeployNttSpokeToken: TOKEN_NAME env var not set."
        );
        bytes memory tokenSymbolBytes = bytes(tokenSymbol);
        require(
            tokenSymbolBytes.length > 0,
            "DeployNttSpokeToken: TOKEN_SYMBOL env var not set."
        );
        require(
            deployerPrivateKey != 0,
            "DeployNttSpokeToken: PRIVATE_KEY env var not set."
        );

        console.log("Deploying MyNttSpokeToken...");
        console.log("  Deployer:", deployerAddress);
        console.log("  Token Name:", tokenName);
        console.log("  Token Symbol:", tokenSymbol);

        // --- Deployment --- //
        vm.startBroadcast(deployerPrivateKey);

        token = new NTTToken(tokenName, tokenSymbol);

        vm.stopBroadcast();

        // --- Output --- //
        console.log("\nMyNttSpokeToken deployed successfully!");
        console.log("  Token Address:", address(token));
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
    }
}
