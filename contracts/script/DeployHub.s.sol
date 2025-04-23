// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PeridotHub} from "../contracts/PeridotHub.sol";
import {EIP1967Proxy} from "../contracts/proxy/Proxy.sol"; // Import the proxy

/**
 * @title DeployHub
 * @notice Deploys the PeridotHub logic contract and an EIP1967Proxy pointing to it.
 * @dev Initializes the PeridotHub logic through the proxy.
 */
contract DeployHub is Script {
    function run() external returns (address payable proxyAddress) {
        // PeridotHub constructor arguments
        address wormhole = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        address tokenBridge = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;
        address peridottroller = 0xfB3f8837B1Ad7249C1B253898b3aa7FaB22E68aD;
        address relayer = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;

        // Proxy configuration
        address proxyAdmin = 0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // Admin for the proxy itself (can upgrade)
        address hubOwner = 0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // Owner of PeridotHub logic (calls onlyOwner functions)

        // Deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // --- Input Validation --- //
        require(wormhole != address(0), "HUB_WORMHOLE_ADDRESS not set");
        require(tokenBridge != address(0), "HUB_TOKEN_BRIDGE_ADDRESS not set");
        require(peridottroller != address(0), "PERIDOTTROLLER_ADDRESS not set");
        require(relayer != address(0), "HUB_RELAYER_ADDRESS not set");
        require(proxyAdmin != address(0), "PROXY_ADMIN not set");
        require(hubOwner != address(0), "HUB_OWNER not set");
        require(deployerPrivateKey != 0, "PRIVATE_KEY not set");

        // --- Deployment --- //
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying PeridotHub Logic...");
        PeridotHub hubLogic = new PeridotHub(
            wormhole,
            tokenBridge,
            peridottroller,
            relayer
        );
        address logicAddress = address(hubLogic);
        console.log("  PeridotHub Logic Deployed:", logicAddress);

        console.log("Deploying EIP1967Proxy for PeridotHub...");
        console.log("  Initial Implementation:", logicAddress);
        console.log("  Proxy Admin:", proxyAdmin);
        EIP1967Proxy hubProxy = new EIP1967Proxy(logicAddress, proxyAdmin);
        proxyAddress = payable(address(hubProxy));
        console.log("  PeridotHub Proxy Deployed:", proxyAddress);

        console.log("Initializing PeridotHub via Proxy...");
        console.log("  Setting Hub Owner:", hubOwner);
        PeridotHub(proxyAddress).initialize(hubOwner);

        vm.stopBroadcast();

        // --- Output & Verification --- //
        console.log("\n--- Deployment Summary ---");
        console.log("PeridotHub Logic Address:", logicAddress);
        console.log("PeridotHub Proxy Address:", proxyAddress);
        console.log("Proxy Admin Address:", EIP1967Proxy(proxyAddress).admin());
        console.log(
            "PeridotHub Owner (via Proxy):",
            PeridotHub(proxyAddress).owner()
        );

        require(
            EIP1967Proxy(proxyAddress).implementation() == logicAddress,
            "Proxy implementation mismatch"
        );
        require(
            EIP1967Proxy(proxyAddress).admin() == proxyAdmin,
            "Proxy admin mismatch"
        );
        require(
            PeridotHub(proxyAddress).owner() == hubOwner,
            "Hub owner mismatch after initialization"
        );
        console.log("Deployment and initialization verified successfully!");
    }
}
