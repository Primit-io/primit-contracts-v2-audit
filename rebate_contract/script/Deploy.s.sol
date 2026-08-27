// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/referral/RebateDistributor.sol";

contract DeployRebateDistributorSepolia is Script {
    function run() external returns (RebateDistributor rebateDistributor) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdc = vm.envAddress("USDC_TOKEN_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address backendSigner = vm.envAddress("SIGNER_ADDRESS");
        address referralStorage = vm.envAddress("REFERRAL_STORAGE_ADDRESS");
        string memory domainName = vm.envString("EIP712_REFERRAL_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_REFERRAL_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying RebateDistributor to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDC:", usdc);
        console.log("Vault:", vault);
        console.log("Backend signer:", backendSigner);
        console.log("ReferralStorage:", referralStorage);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        RebateDistributor implementation = new RebateDistributor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                RebateDistributor.initialize,
                (usdc, vault, backendSigner, referralStorage, domainName, domainVersion, admin)
            )
        );
        rebateDistributor = RebateDistributor(address(proxy));
        vm.stopBroadcast();

        console.log("RebateDistributor deployed at:", address(rebateDistributor));
        console.log("RebateDistributor implementation:", address(implementation));
    }
}

contract DeployRebateDistributorMainnet is Script {
    function run() external returns (RebateDistributor rebateDistributor) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdc = vm.envAddress("MAINNET_USDC_ADDRESS");
        address vault = vm.envAddress("MAINNET_VAULT_ADDRESS");
        address backendSigner = vm.envAddress("SIGNER_ADDRESS");
        address referralStorage = vm.envAddress("MAINNET_REFERRAL_STORAGE_ADDRESS");
        string memory domainName = vm.envString("EIP712_REFERRAL_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_REFERRAL_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying RebateDistributor to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDC:", usdc);
        console.log("Vault:", vault);
        console.log("Backend signer:", backendSigner);
        console.log("ReferralStorage:", referralStorage);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        RebateDistributor implementation = new RebateDistributor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                RebateDistributor.initialize,
                (usdc, vault, backendSigner, referralStorage, domainName, domainVersion, admin)
            )
        );
        rebateDistributor = RebateDistributor(address(proxy));
        vm.stopBroadcast();

        console.log("RebateDistributor deployed at:", address(rebateDistributor));
        console.log("RebateDistributor implementation:", address(implementation));
    }
}

contract UpgradeRebateDistributor is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address rebateProxy = vm.envAddress("REBATE_DISTRIBUTOR_ADDRESS");
        string memory domainVersion = vm.envString("EIP712_REFERRAL_DOMAIN_VERSION");

        console.log("=== Upgrading RebateDistributor proxy ===");
        console.log("Proxy:", rebateProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));
        console.log("Domain version:", domainVersion);

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new RebateDistributor());
        RebateDistributor(payable(rebateProxy)).upgradeToAndCall(
            implementation,
            abi.encodeCall(
                RebateDistributor.reinitializeEip712DomainVersion,
                (domainVersion)
            )
        );
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
