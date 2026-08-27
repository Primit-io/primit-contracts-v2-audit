// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/vault/Vault.sol";

contract UpgradeVaultProtocolFeesAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault implementation) {
        uint256 chainId = block.chainid;
        require(chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID, "UpgradeVaultProtocolFeesAvax: AVAX only");

        uint256 ownerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address protocolFeeRecipient = _protocolFeeRecipient();
        require(protocolFeeRecipient != address(0), "UpgradeVaultProtocolFeesAvax: fee recipient is zero");

        console2.log("=== Upgrade Vault + protocol fee recipient ===");
        console2.log("chainid:", chainId);
        console2.log("vault:", vault);
        console2.log("protocolFeeRecipient:", protocolFeeRecipient);

        vm.startBroadcast(ownerPrivateKey);
        implementation = new Vault();
        Vault(payable(vault)).upgradeToAndCall(
            address(implementation), abi.encodeCall(Vault.reinitializeProtocolFees, (protocolFeeRecipient))
        );
        vm.stopBroadcast();

        Vault upgradedVault = Vault(payable(vault));
        console2.log("implementation:", address(implementation));
        console2.log("protocolFeeRecipient:", upgradedVault.protocolFeeRecipient());
        console2.log("depositPaused:", upgradedVault.depositPaused());
        console2.log("withdrawPaused:", upgradedVault.withdrawPaused());
    }

    function _protocolFeeRecipient() internal view returns (address recipient) {
        try vm.envAddress("PROTOCOL_FEE_RECIPIENT") returns (address value) {
            return value;
        } catch {}

        try vm.envAddress("TREASURY_ADDRESS") returns (address value) {
            return value;
        } catch {}

        return vm.envAddress("SETTLEMENT_RECIPIENT");
    }
}
