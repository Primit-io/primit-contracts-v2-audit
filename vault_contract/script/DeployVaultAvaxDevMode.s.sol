// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @title DeployVaultAvaxDevMode
/// @notice **DEV/TEST ONLY** · 允许 hot EOA 单 key 在 mainnet 上部署一套完整 Vault
///         (跳过既有 DeployVaultAvax 强制 SAFE_OWNER_ADDR 的 mainnet check)。
///
/// @dev **⚠️ 不要用于生产**:
///     - 生产走 `DeployVaultAvax.s.sol`(必带 Safe 多签接管,SEC posture 完整)
///     - 本 script 只用于 sprint dev 阶段跑通 PLP 端到端功能测试
///     - v1.1 灰度前必须迁 owner → OneKey/Safe
///
/// @dev SEC-002 leaked ADMIN check 保留(不 skip)· 唯一 skip 的是"mainnet 强制 Safe"。
contract DeployVaultAvaxDevMode is Script {
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;

    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault vault) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "DeployVaultAvaxDevMode: AVAX only"
        );

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        address referralStorage = vm.envAddress("REFERRAL_STORAGE");

        // SEC-002 hard-check 保留
        require(deployer != LEAKED_ADMIN, "DeployVaultAvaxDevMode: SEC-002 deployer");
        require(backendSigner != LEAKED_ADMIN, "DeployVaultAvaxDevMode: SEC-002 backendSigner");

        // Dev mode: owner = deployer(单 key 一梭子)
        address initialOwner = deployer;

        string memory domainName = "Primit Vault Dev";
        string memory domainVersion = "1";

        console2.log("================================================================");
        console2.log("  DeployVaultAvaxDevMode - AVAX single-EOA sprint deploy");
        console2.log("  !!! DEV/TEST ONLY - v1.1 launch requires DeployVaultAvax with Safe");
        console2.log("================================================================");
        console2.log("  chainid:", chainId);
        console2.log("  deployer/owner:", deployer);
        console2.log("  usdc:", usdc);
        console2.log("  backendSigner:", backendSigner);
        console2.log("  domainName:", domainName);
        console2.log("  domainVersion:", domainVersion);

        vm.startBroadcast(deployerPk);

        Vault implementation = new Vault();
        console2.log("[1/2] Vault implementation:", address(implementation));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Vault.initialize,
                (usdc, backendSigner, referralStorage, domainName, domainVersion, initialOwner)
            )
        );
        vault = Vault(address(proxy));
        console2.log("[2/2] Vault proxy:", address(vault));

        vm.stopBroadcast();

        // Post-flight sanity
        console2.log("  vault.usdc():", address(vault.usdc()));
        console2.log("  vault.owner():", vault.owner());
        require(vault.owner() == deployer, "DeployVaultAvaxDevMode: owner mismatch");
    }
}
