// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/liquidation/LiquidationManager.sol";
import "../src/contracts/core/vault/Vault.sol";

contract DeployLiquidationManagerAvax is Script {
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;
    /// D7 (2026-07-24) known-compromised admins
    address constant KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c96A7118d879Cf3a9e39bdC4Ee1D1b4D8;
    address constant KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2402807C183dD25E68AEE3f0Cc4BA;

    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (LiquidationManager manager) {
        uint256 chainId = block.chainid;
        require(chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID, "DeployLiquidationManagerAvax: AVAX only");

        uint256 ownerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);
        address vault = vm.envAddress("VAULT_ADDRESS");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        address oracleSigner = vm.envAddress("ORACLE_SIGNER");
        address settlementRecipient = vm.envAddress("SETTLEMENT_RECIPIENT");

        // SEC-002 + D7 SEC hard locks
        require(owner != LEAKED_ADMIN, "SEC-002: owner == leaked ADMIN");
        require(backendSigner != LEAKED_ADMIN, "SEC-002: backendSigner == leaked ADMIN");
        require(oracleSigner != LEAKED_ADMIN, "SEC-002: oracleSigner == leaked ADMIN");
        require(
            owner != KNOWN_COMPROMISED_ADMIN_1 && owner != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: owner == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            backendSigner != KNOWN_COMPROMISED_ADMIN_1 && backendSigner != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: backendSigner == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            oracleSigner != KNOWN_COMPROMISED_ADMIN_1 && oracleSigner != KNOWN_COMPROMISED_ADMIN_2,
            "D7 SEC: oracleSigner == KNOWN_COMPROMISED_ADMIN"
        );

        address keeper = address(0);
        try vm.envAddress("KEEPER") returns (address configuredKeeper) {
            keeper = configuredKeeper;
        } catch {}

        console2.log("=== Deploying LiquidationManager ===");
        console2.log("chainid:", chainId);
        console2.log("owner:", owner);
        console2.log("vault:", vault);
        console2.log("backendSigner:", backendSigner);
        console2.log("oracleSigner:", oracleSigner);
        console2.log("settlementRecipient:", settlementRecipient);
        console2.log("keeper:", keeper);

        vm.startBroadcast(ownerPrivateKey);
        manager = new LiquidationManager(vault, backendSigner, oracleSigner, settlementRecipient, owner);
        Vault(payable(vault)).setLiquidationManager(address(manager));
        if (keeper != address(0)) {
            manager.setKeeper(keeper, true);
        }
        vm.stopBroadcast();

        console2.log("LiquidationManager:", address(manager));
    }
}
