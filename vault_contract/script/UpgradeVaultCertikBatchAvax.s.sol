// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/vault/Vault.sol";

/// @title UpgradeVaultCertikBatchAvax
/// @notice CertiK batch upgrade: pushes PRI-10 (zero-address checks on
///         Vault.setBackendSigner + Vault.setReferralStorage) live, and
///         carries the PRI-06 onlyOwner fix on reinitializeSettlementCaps
///         as defense-in-depth (the PRI-06 attack window is already
///         closed on mainnet by _initialized == 5, but shipping the fix
///         keeps the reinitializer contract consistent across all
///         sibling reinitializers).
///
/// @dev    upgradeToAndCall(newImpl, "") · no reinitializer · no storage
///         migration · both fixes are pure revert-logic additions.
///
/// Env:
///   ADMIN_PRIVATE_KEY  = Vault owner (V2 hot key 0x2821c28b...)
///   VAULT_ADDRESS      = 0xDF19d902fcB6295366A06620F76DCb49e686C403 (mainnet)
contract UpgradeVaultCertikBatchAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault implementation) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "UpgradeVaultCertikBatchAvax: AVAX only"
        );

        uint256 ownerPk = vm.envUint("ADMIN_PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "UpgradeVaultCertikBatchAvax: vault zero");

        Vault vault = Vault(payable(vaultAddr));

        // snapshot state BEFORE the upgrade so we can assert nothing drifted
        address backendSignerBefore = vault.backendSigner();
        address referralStorageBefore = address(vault.referralStorage());
        address liquidationManagerBefore = vault.liquidationManager();
        address ownerBefore = vault.owner();

        console2.log("=== UpgradeVaultCertikBatchAvax (PRI-06 + PRI-10) ===");
        console2.log("chainid              :", chainId);
        console2.log("Vault proxy          :", vaultAddr);
        console2.log("backendSigner before :", backendSignerBefore);
        console2.log("referralStorage b4   :", referralStorageBefore);
        console2.log("liquidationManager b4:", liquidationManagerBefore);
        console2.log("owner before         :", ownerBefore);

        vm.startBroadcast(ownerPk);
        implementation = new Vault();
        vault.upgradeToAndCall(address(implementation), "");
        vm.stopBroadcast();

        console2.log("new implementation   :", address(implementation));

        // hard post-checks: state preserved, no storage layout drift
        require(vault.backendSigner() == backendSignerBefore, "UpgradeVaultCertikBatchAvax: backendSigner drifted");
        require(
            address(vault.referralStorage()) == referralStorageBefore,
            "UpgradeVaultCertikBatchAvax: referralStorage drifted"
        );
        require(
            vault.liquidationManager() == liquidationManagerBefore,
            "UpgradeVaultCertikBatchAvax: liquidationManager drifted"
        );
        require(vault.owner() == ownerBefore, "UpgradeVaultCertikBatchAvax: owner drifted");

        console2.log("post-check: state preserved (backendSigner / referralStorage / liquidationManager / owner)");
    }
}
