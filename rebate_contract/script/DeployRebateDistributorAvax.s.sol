// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RebateDistributor} from "../src/contracts/core/referral/RebateDistributor.sol";

/// @notice V2 · Deploy RebateDistributor as UUPS Proxy on AVAX C-Chain
///
/// Env:
///   PRIVATE_KEY         = deployer EOA (Lee's V2 hot key)
///   USDC_ADDRESS        = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E (mainnet · native USDC)
///   VAULT_ADDRESS       = V2 Vault Proxy (returned by DeployVaultAvax)
///   BACKEND_SIGNER      = backend signer EOA
///   REFERRAL_STORAGE    = V2 ReferralStorage Proxy
///   ADMIN               = owner (transferred to SAFE later)
contract DeployRebateDistributorAvax is Script {
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;
    address constant KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c96A7118d879Cf3a9e39bdC4Ee1D1b4D8;
    address constant KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2402807C183dD25E68AEE3f0Cc4BA;
    address constant EXPECTED_USDC_MAINNET = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    uint256 constant AVAX_MAINNET_CHAINID = 43_114;
    uint256 constant FUJI_CHAINID = 43_113;

    function run() external returns (address proxy, address impl) {
        uint256 chainId = block.chainid;
        require(
            chainId == AVAX_MAINNET_CHAINID || chainId == FUJI_CHAINID,
            "DeployRebateDistributorAvax: AVAX only"
        );

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        address referralStorage = vm.envAddress("REFERRAL_STORAGE");
        address admin = vm.envAddress("ADMIN");

        // SEC-002 + D7 SEC hard locks
        require(deployer != LEAKED_ADMIN, "SEC-002: deployer == leaked ADMIN");
        require(backendSigner != LEAKED_ADMIN, "SEC-002: backendSigner == leaked ADMIN");
        require(admin != LEAKED_ADMIN, "SEC-002: admin == leaked ADMIN");
        require(
            deployer != KNOWN_COMPROMISED_ADMIN_1 && deployer != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: deployer == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            backendSigner != KNOWN_COMPROMISED_ADMIN_1 && backendSigner != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: backendSigner == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            admin != KNOWN_COMPROMISED_ADMIN_1 && admin != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: admin == KNOWN_COMPROMISED_ADMIN"
        );

        // Mainnet USDC hard-lock
        if (chainId == AVAX_MAINNET_CHAINID) {
            require(usdc == EXPECTED_USDC_MAINNET, "DeployRebateDistributorAvax: mainnet must use native USDC");
        }

        string memory domainName = chainId == AVAX_MAINNET_CHAINID ? "Primit Rebate AVAX" : "Primit Rebate AVAX Fuji";

        console2.log("=== DeployRebateDistributorAvax ===");
        console2.log("  chainid          :", chainId);
        console2.log("  deployer         :", deployer);
        console2.log("  usdc             :", usdc);
        console2.log("  vault            :", vaultAddr);
        console2.log("  backendSigner    :", backendSigner);
        console2.log("  referralStorage  :", referralStorage);
        console2.log("  admin            :", admin);

        vm.startBroadcast(deployerPk);
        RebateDistributor implContract = new RebateDistributor();
        bytes memory initData = abi.encodeCall(
            RebateDistributor.initialize,
            (usdc, vaultAddr, backendSigner, referralStorage, domainName, "1.0.0", admin)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implContract), initData);
        vm.stopBroadcast();

        impl = address(implContract);
        proxy = address(proxyContract);
        console2.log("  RebateDistributor impl  :", impl);
        console2.log("  RebateDistributor proxy :", proxy);
    }
}
