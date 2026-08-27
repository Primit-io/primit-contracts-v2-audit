// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";

/// @title UpgradePlpImplAvax
/// @notice CertiK PRI-03 · deploy hardened LiquidityVault impl (constructor _disableInitializers) +
///         UUPS upgradeToAndCall proxy at 0xc78786e840b8179b2f3fdbf0fedf69466a51ddf7.
///
/// @dev No state migration · no reinitializer · empty init data.
///
/// Env:
///   ADMIN_PRIVATE_KEY = holder of DEFAULT_ADMIN_ROLE on PLP proxy (V2 hot key)
///   PLP_PROXY_ADDRESS = 0xc78786e840b8179b2f3fdbf0fedf69466a51ddf7 (mainnet PLP UUPS proxy)
contract UpgradePlpImplAvax is Script {
    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (LiquidityVault implementation) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "UpgradePlpImplAvax: AVAX only"
        );

        uint256 ownerPk = vm.envUint("ADMIN_PRIVATE_KEY");
        address plpProxy = vm.envAddress("PLP_PROXY_ADDRESS");
        require(plpProxy != address(0), "UpgradePlpImplAvax: plpProxy zero");

        LiquidityVault plp = LiquidityVault(plpProxy);
        bytes32 markerBefore = plp.deploymentMarker();
        uint256 totalAssetsBefore = plp.totalAssets();
        address usdcBefore = plp.usdc();
        address vaultBefore = plp.vault();

        console2.log("=== UpgradePlpImplAvax (PRI-03) ===");
        console2.log("chainid            :", chainId);
        console2.log("PLP proxy          :", plpProxy);
        console2.log("marker before      :", uint256(markerBefore));
        console2.log("totalAssets before :", totalAssetsBefore);
        console2.log("usdc before        :", usdcBefore);
        console2.log("vault before       :", vaultBefore);

        vm.startBroadcast(ownerPk);
        implementation = new LiquidityVault();
        plp.upgradeToAndCall(address(implementation), "");
        vm.stopBroadcast();

        console2.log("new implementation :", address(implementation));

        require(plp.deploymentMarker() == markerBefore, "UpgradePlpImplAvax: marker changed");
        require(plp.totalAssets() == totalAssetsBefore, "UpgradePlpImplAvax: totalAssets changed");
        require(plp.usdc() == usdcBefore, "UpgradePlpImplAvax: usdc changed");
        require(plp.vault() == vaultBefore, "UpgradePlpImplAvax: vault changed");

        try LiquidityVault(address(implementation)).initialize(
            address(0xdead), address(0xdead), address(0xdead), address(0xdead), address(0xdead)
        ) {
            revert("UpgradePlpImplAvax: raw impl initialize() did NOT revert - _disableInitializers missing");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == bytes4(keccak256("InvalidInitialization()")),
                "UpgradePlpImplAvax: raw impl reverted but not with InvalidInitialization()"
            );
        }

        console2.log("post-check: state preserved + raw impl initialize() locked");
    }
}
