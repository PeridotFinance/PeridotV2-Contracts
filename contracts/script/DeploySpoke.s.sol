// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PeridotSpoke} from "../contracts/PeridotSpoke.sol";
import {EIP1967Proxy} from "../contracts/proxy/Proxy.sol"; // Import the proxy

/**
 * @title DeploySpoke
 * @notice Deploys the PeridotSpoke logic contract and an EIP1967Proxy pointing to it.
 * @dev Initializes the PeridotSpoke logic through the proxy.
 */
contract DeploySpoke is Script {
    function run() external returns (address payable proxyAddress) {
        // --- Configuration --- //

        // PeridotSpoke constructor arguments
        address wormhole = 0x79A1027a6A159502049F10906D333EC57E95F083;
        address relayer = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        address tokenBridge = 0x86F55A04690fd7815A3D802bD587e83eA888B239;
        uint16 hubChainId = 10003;
        address hubAddress = 0x8F9d1f504B13726d0977216CF81fB1e7d81a497C; // This should be the HUB PROXY address

        // Proxy configuration
        address proxyAdmin = 0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // Admin for the proxy itself
        address spokeOwner = 0xF450B38cccFdcfAD2f98f7E4bB533151a2fB00E9; // Owner of PeridotSpoke logic

        // Deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // --- Input Validation --- //
        require(wormhole != address(0), "SPOKE_WORMHOLE_ADDRESS not set");
        require(relayer != address(0), "SPOKE_RELAYER_ADDRESS not set");
        require(
            tokenBridge != address(0),
            "SPOKE_TOKEN_BRIDGE_ADDRESS not set"
        );
        require(hubChainId != 0, "HUB_CHAIN_ID not set or zero");
        require(hubAddress != address(0), "HUB_ADDRESS (Hub Proxy) not set");
        require(proxyAdmin != address(0), "PROXY_ADMIN not set");
        require(spokeOwner != address(0), "SPOKE_OWNER not set");
        require(deployerPrivateKey != 0, "PRIVATE_KEY not set");

        // --- Deployment --- //
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying PeridotSpoke Logic...");
        PeridotSpoke spokeLogic = new PeridotSpoke(
            wormhole,
            relayer,
            tokenBridge,
            hubChainId,
            hubAddress
        );
        address logicAddress = address(spokeLogic);
        console.log("  PeridotSpoke Logic Deployed:", logicAddress);

        console.log("Deploying EIP1967Proxy for PeridotSpoke...");
        console.log("  Initial Implementation:", logicAddress);
        console.log("  Proxy Admin:", proxyAdmin);
        EIP1967Proxy spokeProxy = new EIP1967Proxy(logicAddress, proxyAdmin);
        proxyAddress = payable(address(spokeProxy));
        console.log("  PeridotSpoke Proxy Deployed:", proxyAddress);

        console.log("Initializing PeridotSpoke via Proxy...");
        console.log("  Setting Spoke Owner:", spokeOwner);
        PeridotSpoke(proxyAddress).initialize(spokeOwner);

        vm.stopBroadcast();

        // --- Output & Verification --- //
        console.log("\n--- Deployment Summary ---");
        console.log("PeridotSpoke Logic Address:", logicAddress);
        console.log("PeridotSpoke Proxy Address:", proxyAddress);
        console.log("Proxy Admin Address:", EIP1967Proxy(proxyAddress).admin());
        console.log(
            "PeridotSpoke Owner (via Proxy):",
            PeridotSpoke(proxyAddress).owner()
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
            PeridotSpoke(proxyAddress).owner() == spokeOwner,
            "Spoke owner mismatch after initialization"
        );
        console.log("Deployment and initialization verified successfully!");

        return proxyAddress;
    }
}
