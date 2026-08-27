// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/vault/Vault.sol";

/// @title UpgradeVaultAddPLPAddressAvax
/// @notice 主网 Vault 升级到含 PLP 集成接口的新 impl,并 reinitializer(5) 授权 PLP 白名单。
/// @dev 参考既有 UpgradeVaultSettlementCapsAvax pattern。error_log root cause fix:
///      主网 Vault proxy 0x0A30... 当前 impl 0xFB4F... 不含 PLP selectors
///      (debitFromUser / creditToUser / plpVaultAddress),导致 PLP.deposit → Vault.debitFromUser
///      fallback revert。本 script 一次性 deploy 新 impl + upgradeToAndCall reinitializeAddPLPAddress。
///
/// @dev Env 前置:
///   ADMIN_PRIVATE_KEY = Vault owner 私钥(与 D1 部署 admin 同一把)
///   VAULT_ADDRESS     = Vault proxy 地址 0x0A30176bba21d262cDc652814b8C2A4c9a397b1b
///   PLP_VAULT_ADDRESS = LiquidityVault 地址 0x9153De448f2D358E6fE1d07e454dd72d2B0E1de2
contract UpgradeVaultAddPLPAddressAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault implementation) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID, "UpgradeVaultAddPLPAddressAvax: AVAX only"
        );

        uint256 ownerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address plpVault = vm.envAddress("PLP_VAULT_ADDRESS");
        require(vault != address(0), "UpgradeVaultAddPLPAddressAvax: vault zero");
        require(plpVault != address(0), "UpgradeVaultAddPLPAddressAvax: plpVault zero");

        console2.log("=== Upgrade Vault + reinitializeAddPLPAddress ===");
        console2.log("chainid:", chainId);
        console2.log("vault proxy:", vault);
        console2.log("plpVault:", plpVault);
        console2.log("(this run will 1) deploy new Vault impl 2) upgradeToAndCall reinitializeAddPLPAddress)");

        vm.startBroadcast(ownerPrivateKey);
        implementation = new Vault();
        Vault(payable(vault))
            .upgradeToAndCall(address(implementation), abi.encodeCall(Vault.reinitializeAddPLPAddress, (plpVault)));
        vm.stopBroadcast();

        // ---- On-chain post-condition checks(hard-fail 若不一致)----
        console2.log("new implementation:", address(implementation));
        address readBack = Vault(payable(vault)).plpVaultAddress();
        console2.log("plpVaultAddress on Vault:", readBack);
        require(readBack == plpVault, "UpgradeVaultAddPLPAddressAvax: plpVaultAddress mismatch after upgrade");
    }
}
