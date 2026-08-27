// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/contracts/referral/ReferralStorage.sol";

/// @title UpgradeReferralStorageAvax
/// @notice CertiK PRI-08 · deploy hardened ReferralStorage impl (setReferrerTier
///         now rejects uninitialized tier ids) + UUPS upgradeToAndCall proxy at
///         0x8426de38a4b7b36b04d91826e28d8d3a29394d57.
/// @dev No state migration · no reinitializer · empty init data.
///
/// Env:
///   ADMIN_PRIVATE_KEY               = ReferralStorage ADMIN_ROLE holder
///   REFERRAL_STORAGE_PROXY_ADDRESS  = 0x8426de38a4b7b36b04d91826e28d8d3a29394d57 (mainnet)
contract UpgradeReferralStorageAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (ReferralStorage implementation) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "UpgradeReferralStorageAvax: AVAX only"
        );

        uint256 ownerPk = vm.envUint("ADMIN_PRIVATE_KEY");
        address rsProxy = vm.envAddress("REFERRAL_STORAGE_PROXY_ADDRESS");
        require(rsProxy != address(0), "UpgradeReferralStorageAvax: proxy zero");

        ReferralStorage rs = ReferralStorage(rsProxy);

        console2.log("=== UpgradeReferralStorageAvax (PRI-08) ===");
        console2.log("chainid            :", chainId);
        console2.log("ReferralStorage    :", rsProxy);

        vm.startBroadcast(ownerPk);
        implementation = new ReferralStorage();
        rs.upgradeToAndCall(address(implementation), "");
        vm.stopBroadcast();

        console2.log("new implementation :", address(implementation));

        // Post-check: raw impl initialize() must revert InvalidInitialization()
        // (constructor _disableInitializers already ships on the sibling contract
        // per the mainnet baseline; if that ever regresses this catches it here).
        try ReferralStorage(address(implementation)).initialize(address(0xdead)) {
            revert("UpgradeReferralStorageAvax: raw impl initialize() did NOT revert - _disableInitializers missing");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == bytes4(keccak256("InvalidInitialization()")),
                "UpgradeReferralStorageAvax: raw impl reverted but not with InvalidInitialization()"
            );
        }

        console2.log("post-check: raw impl initialize() locked");
    }
}
