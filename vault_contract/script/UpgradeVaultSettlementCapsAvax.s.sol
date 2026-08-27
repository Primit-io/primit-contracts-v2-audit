// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/vault/Vault.sol";

contract UpgradeVaultSettlementCapsAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault implementation) {
        uint256 chainId = block.chainid;
        require(chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID, "UpgradeVaultSettlementCapsAvax: AVAX only");

        uint256 ownerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vault = vm.envAddress("VAULT_ADDRESS");
        uint256 globalCap = vm.envUint("DAILY_SETTLEMENT_CREDIT_CAP");
        uint256 perUserCap = vm.envUint("DAILY_USER_SETTLEMENT_CREDIT_CAP");
        require(globalCap != 0, "UpgradeVaultSettlementCapsAvax: global cap is zero");
        require(perUserCap != 0, "UpgradeVaultSettlementCapsAvax: per-user cap is zero");
        require(perUserCap <= globalCap, "UpgradeVaultSettlementCapsAvax: per-user cap > global cap");

        console2.log("=== Upgrade Vault + settlement caps ===");
        console2.log("chainid:", chainId);
        console2.log("vault:", vault);
        console2.log("globalCap:", globalCap);
        console2.log("perUserCap:", perUserCap);

        vm.startBroadcast(ownerPrivateKey);
        implementation = new Vault();
        Vault(payable(vault))
            .upgradeToAndCall(
                address(implementation), abi.encodeCall(Vault.reinitializeSettlementCaps, (globalCap, perUserCap))
            );
        vm.stopBroadcast();

        console2.log("implementation:", address(implementation));
        console2.log("dailySettlementCreditCap:", Vault(payable(vault)).dailySettlementCreditCap());
        console2.log("dailyUserSettlementCreditCap:", Vault(payable(vault)).dailyUserSettlementCreditCap());
    }
}
