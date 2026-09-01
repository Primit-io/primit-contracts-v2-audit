// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/vault/Vault.sol";

contract DeployVaultSepolia is Script {
    function run() external returns (Vault vault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdc = vm.envAddress("USDC_TOKEN_ADDRESS");
        address backendSigner = vm.envAddress("SIGNER_ADDRESS");
        address referralStorage = vm.envAddress("REFERRAL_STORAGE_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying Vault to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDC:", usdc);
        console.log("Backend signer:", backendSigner);
        console.log("ReferralStorage:", referralStorage);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        Vault implementation = new Vault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Vault.initialize,
                (Vault.InitParams({
                    usdc: usdc,
                    backendSigner: backendSigner,
                    referralStorage: referralStorage,
                    domainName: domainName,
                    domainVersion: domainVersion,
                    owner: admin,
                    // PRI-11 · required for fresh deploy — set via env or override before broadcast
                    plpVault: vm.envOr("PLP_VAULT_ADDRESS", address(0xDEAD1)),
                    liquidationManager: vm.envOr("LIQUIDATION_MANAGER_ADDRESS", address(0xDEAD2)),
                    protocolFeeRecipient: vm.envOr("PROTOCOL_FEE_RECIPIENT", address(0xDEAD3)),
                    dailySettlementCreditCap: vm.envOr("DAILY_SETTLEMENT_CREDIT_CAP", uint256(0)),
                    dailyUserSettlementCreditCap: vm.envOr("DAILY_USER_SETTLEMENT_CREDIT_CAP", uint256(0))
                }))
            )
        );
        vault = Vault(address(proxy));
        vm.stopBroadcast();

        console.log("Vault deployed at:", address(vault));
        console.log("Vault implementation:", address(implementation));
    }
}

contract DeployVaultMainnet is Script {
    function run() external returns (Vault vault) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdc = vm.envAddress("MAINNET_USDC_ADDRESS");
        address backendSigner = vm.envAddress("SIGNER_ADDRESS");
        address referralStorage = vm.envAddress("MAINNET_REFERRAL_STORAGE_ADDRESS");
        string memory domainName = vm.envString("EIP712_DOMAIN_NAME");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying Vault to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDC:", usdc);
        console.log("Backend signer:", backendSigner);
        console.log("ReferralStorage:", referralStorage);
        console.log("Domain:", domainName);
        console.log("Domain version:", domainVersion);
        console.log("Owner:", admin);

        vm.startBroadcast(deployerPrivateKey);
        Vault implementation = new Vault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Vault.initialize,
                (Vault.InitParams({
                    usdc: usdc,
                    backendSigner: backendSigner,
                    referralStorage: referralStorage,
                    domainName: domainName,
                    domainVersion: domainVersion,
                    owner: admin,
                    // PRI-11 · required for fresh deploy — set via env or override before broadcast
                    plpVault: vm.envOr("PLP_VAULT_ADDRESS", address(0xDEAD1)),
                    liquidationManager: vm.envOr("LIQUIDATION_MANAGER_ADDRESS", address(0xDEAD2)),
                    protocolFeeRecipient: vm.envOr("PROTOCOL_FEE_RECIPIENT", address(0xDEAD3)),
                    dailySettlementCreditCap: vm.envOr("DAILY_SETTLEMENT_CREDIT_CAP", uint256(0)),
                    dailyUserSettlementCreditCap: vm.envOr("DAILY_USER_SETTLEMENT_CREDIT_CAP", uint256(0))
                }))
            )
        );
        vault = Vault(address(proxy));
        vm.stopBroadcast();

        console.log("Vault deployed at:", address(vault));
        console.log("Vault implementation:", address(implementation));
    }
}

contract UpgradeVault is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vaultProxy = vm.envAddress("VAULT_ADDRESS");
        string memory domainVersion = vm.envString("EIP712_DOMAIN_VERSION");

        console.log("=== Upgrading Vault proxy ===");
        console.log("Proxy:", vaultProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));
        console.log("Domain version:", domainVersion);

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new Vault());
        Vault(payable(vaultProxy))
            .upgradeToAndCall(implementation, abi.encodeCall(Vault.reinitializeEip712DomainVersion, (domainVersion)));
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}

contract UpgradeVaultNoReinit is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vaultProxy = vm.envAddress("VAULT_ADDRESS");

        console.log("=== Upgrading Vault proxy without reinitializer ===");
        console.log("Proxy:", vaultProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new Vault());
        Vault(payable(vaultProxy)).upgradeToAndCall(implementation, bytes(""));
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
