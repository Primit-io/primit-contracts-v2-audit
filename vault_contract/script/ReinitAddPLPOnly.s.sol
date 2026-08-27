// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @notice Dev-only:Vault 已经是新 impl(deploy 时用了新代码),只需调 reinitializer(5) 授权 PLP 白名单
contract ReinitAddPLPOnly is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address plpVault = vm.envAddress("PLP_VAULT_ADDRESS");

        console2.log("Vault:", vault);
        console2.log("PLP:", plpVault);

        vm.startBroadcast(ownerPk);
        Vault(payable(vault)).reinitializeAddPLPAddress(plpVault);
        vm.stopBroadcast();

        address readBack = Vault(payable(vault)).plpVaultAddress();
        console2.log("plpVaultAddress on Vault:", readBack);
        require(readBack == plpVault, "ReinitAddPLPOnly: mismatch");
    }
}
