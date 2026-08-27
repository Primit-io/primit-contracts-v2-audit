// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/core/referral/RebateDistributor.sol";

/// @title UpgradeRebateDistributorAvax
/// @notice CertiK PRI-09 · deploy hardened RebateDistributor impl
///         (batchSyncRebates now enforces strict ascending user order, making
///         duplicate recipients impossible in a single batch and reverting
///         DuplicateOrUnsortedRecipient) + UUPS upgradeToAndCall proxy at
///         0x726c54c38119d66e8d2b5d7339b57d8b47e48a3b.
///
/// @dev No state migration · no reinitializer · empty init data.
///
/// Env:
///   ADMIN_PRIVATE_KEY                 = RebateDistributor owner (V2 hot key)
///   REBATE_DISTRIBUTOR_PROXY_ADDRESS  = 0x726c54c38119d66e8d2b5d7339b57d8b47e48a3b (mainnet)
contract UpgradeRebateDistributorAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (RebateDistributor implementation) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "UpgradeRebateDistributorAvax: AVAX only"
        );

        uint256 ownerPk = vm.envUint("ADMIN_PRIVATE_KEY");
        address rdProxy = vm.envAddress("REBATE_DISTRIBUTOR_PROXY_ADDRESS");
        require(rdProxy != address(0), "UpgradeRebateDistributorAvax: proxy zero");

        RebateDistributor rd = RebateDistributor(rdProxy);

        console2.log("=== UpgradeRebateDistributorAvax (PRI-09) ===");
        console2.log("chainid            :", chainId);
        console2.log("RebateDistributor  :", rdProxy);

        vm.startBroadcast(ownerPk);
        implementation = new RebateDistributor();
        rd.upgradeToAndCall(address(implementation), "");
        vm.stopBroadcast();

        console2.log("new implementation :", address(implementation));

        // Post-check: raw impl initialize() must revert InvalidInitialization()
        // (constructor _disableInitializers is expected on the hardened impl).
        try RebateDistributor(address(implementation)).initialize(
            address(0xdead), address(0xdead), address(0xdead), address(0xdead), "x", "x", address(0xdead)
        ) {
            revert("UpgradeRebateDistributorAvax: raw impl initialize() did NOT revert - _disableInitializers missing");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == bytes4(keccak256("InvalidInitialization()")),
                "UpgradeRebateDistributorAvax: raw impl reverted but not with InvalidInitialization()"
            );
        }

        console2.log("post-check: raw impl initialize() locked");
    }
}
