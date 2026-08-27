// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/referral/ReferralStorage.sol";

/// @title DeployReferralStorageAvax
/// @notice One-shot deploy of ReferralStorage UUPS proxy on AVAX C-Chain
///         (mainnet 43114) or Fuji testnet (43113). Companion of
///         DeployVaultAvax.s.sol — Vault.initialize requires a deployed
///         ReferralStorage address as input.
///
/// Design reference: `internal-docs/DESIGN-2026-0512-001-AVAX-Vault-Settlement.md`
///                   §3.3 Phase 1 step 1 (Fuji) / Phase 3 step 11 (mainnet).
///
/// Key difference from DeployVaultAvax: ReferralStorage uses OpenZeppelin
/// AccessControl, NOT Ownable. Admin role takeover therefore requires two
/// calls (grant + revoke) instead of transferOwnership, but they fit in the
/// same broadcast batch so no EOA-only window exists.
///
/// Hard pre-conditions:
///   1. chain-id MUST be 43113 (Fuji) or 43114 (AVAX mainnet).
///   2. SEC-2026-0428-002 interlock: deployer / admin / safeOwner MUST NOT
///      equal the leaked ADMIN 0xadFF12DF…E40.
///   3. (Mainnet only) SAFE_OWNER_ADDR must be set. After deploy:
///        grantRole(DEFAULT_ADMIN_ROLE, Safe)
///        grantRole(ADMIN_ROLE,         Safe)
///        revokeRole(ADMIN_ROLE,        deployer)
///        revokeRole(DEFAULT_ADMIN_ROLE, deployer)
///      All in the SAME broadcast batch.
///
/// Run (Fuji):
///     export PRIVATE_KEY=<Fuji deployer>
///     export ADMIN=<Fuji admin EOA — initial admin before Safe takeover>
///     forge script script/DeployReferralStorageAvax.s.sol:DeployReferralStorageAvax \
///       --rpc-url https://api.avax-test.network/ext/bc/C/rpc \
///       --broadcast --slow --verify --etherscan-api-key $SNOWTRACE_API_KEY
///
/// Run (Mainnet):
///     export PRIVATE_KEY=<KMS-issued mainnet deployer>
///     export SAFE_OWNER_ADDR=<Mainnet Safe 3-of-5>
///     forge script ... same as Fuji but with mainnet RPC
contract DeployReferralStorageAvax is Script {
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;

    /// D7 (2026-07-24) known-compromised admins
    address constant KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c96A7118d879Cf3a9e39bdC4Ee1D1b4D8;
    address constant KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2402807C183dD25E68AEE3f0Cc4BA;

    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (ReferralStorage rs) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "DeployReferralStorageAvax: must run on AVAX 43113 (Fuji) or 43114 (mainnet)"
        );

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        // ADMIN env optional — only used on Fuji path
        address adminEnv;
        try vm.envAddress("ADMIN") returns (address a) {
            adminEnv = a;
        } catch {
            adminEnv = address(0);
        }

        // SEC-002 interlock on all 3 roles
        require(
            deployer != LEAKED_ADMIN,
            "DeployReferralStorageAvax: SEC-002 - deployer == leaked ADMIN"
        );
        require(
            adminEnv != LEAKED_ADMIN,
            "DeployReferralStorageAvax: SEC-002 - admin == leaked ADMIN"
        );
        // D7 SEC lock
        require(
            deployer != KNOWN_COMPROMISED_ADMIN_1 && deployer != KNOWN_COMPROMISED_ADMIN_2,
            "DeployReferralStorageAvax: D7 SEC - deployer == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            adminEnv != KNOWN_COMPROMISED_ADMIN_1 && adminEnv != KNOWN_COMPROMISED_ADMIN_2,
            "DeployReferralStorageAvax: D7 SEC - admin == KNOWN_COMPROMISED_ADMIN"
        );

        // Mainnet: SAFE_OWNER_ADDR required for batched takeover
        // OR explicit opt-in ALLOW_MAINNET_EOA_OWNER=true (V2 clean-slate: EOA deploy first, transfer to SAFE later)
        address safeOwner = address(0);
        if (chainId == AVAX_MAINNET_CHAINID) {
            bool allowEoa = false;
            try vm.envBool("ALLOW_MAINNET_EOA_OWNER") returns (bool v) {
                allowEoa = v;
            } catch {}

            try vm.envAddress("SAFE_OWNER_ADDR") returns (address s) {
                safeOwner = s;
            } catch {
                require(allowEoa, "DeployReferralStorageAvax: mainnet requires SAFE_OWNER_ADDR OR ALLOW_MAINNET_EOA_OWNER=true");
            }
            if (safeOwner != address(0)) {
                require(
                    safeOwner != LEAKED_ADMIN,
                    "DeployReferralStorageAvax: SAFE_OWNER_ADDR invalid"
                );
            }
        }

        // Initial admin: mainnet uses deployer (so grant/revoke succeeds);
        // Fuji uses ADMIN env value (Safe not yet ready).
        address initialAdmin;
        if (safeOwner != address(0)) {
            initialAdmin = deployer;
        } else {
            require(
                adminEnv != address(0),
                "DeployReferralStorageAvax: ADMIN env required when SAFE_OWNER_ADDR unset (Fuji)"
            );
            initialAdmin = adminEnv;
        }

        console2.log("================================================================");
        console2.log("  DeployReferralStorageAvax");
        console2.log("================================================================");
        console2.log("  chainid       :", chainId);
        console2.log("  network       :", chainId == AVAX_MAINNET_CHAINID ? "AVAX mainnet" : "AVAX Fuji");
        console2.log("  deployer      :", deployer);
        console2.log("  initialAdmin  :", initialAdmin);
        console2.log("  ADMIN env     :", adminEnv);
        console2.log("  safeOwner     :", safeOwner);
        console2.log("");

        vm.startBroadcast(deployerPk);

        // Step 1: deploy implementation
        ReferralStorage impl = new ReferralStorage();
        console2.log("[1/3] ReferralStorage impl:", address(impl));

        // Step 2: deploy proxy + initialize(initialAdmin)
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ReferralStorage.initialize, (initialAdmin))
        );
        rs = ReferralStorage(address(proxy));
        console2.log("[2/3] ReferralStorage proxy:", address(rs));

        // Step 3: mainnet — grant roles to Safe + revoke from deployer in same batch
        if (safeOwner != address(0)) {
            bytes32 defaultAdmin = rs.DEFAULT_ADMIN_ROLE();
            bytes32 adminRole = rs.ADMIN_ROLE();

            rs.grantRole(defaultAdmin, safeOwner);
            rs.grantRole(adminRole, safeOwner);
            rs.revokeRole(adminRole, deployer);
            rs.revokeRole(defaultAdmin, deployer);
            console2.log("[3/3] Roles ->            :", safeOwner);

            require(
                rs.hasRole(defaultAdmin, safeOwner) && !rs.hasRole(defaultAdmin, deployer),
                "DeployReferralStorageAvax: role takeover failed post-condition"
            );
        } else {
            console2.log("[3/3] Roles kept on       :", initialAdmin, "(Fuji - Safe takeover later)");
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("================================================================");
        console2.log("  DEPLOY COMPLETE");
        console2.log("");
        if (chainId == FUJI_CHAINID) {
            console2.log("  Next:");
            console2.log("    1. Add address to deployments/fuji.json");
            console2.log("    2. Pass this address as REFERRAL_STORAGE env to DeployVaultAvax");
            console2.log("    3. Phase 2: grantRole(DEFAULT_ADMIN_ROLE, Safe) + revokeRole(deployer)");
        } else {
            console2.log("  Next:");
            console2.log("    1. Add address to deployments/mainnet.json");
            console2.log("    2. Pass this address as REFERRAL_STORAGE env to DeployVaultAvax");
            console2.log("    3. Verify role takeover:");
            console2.log("       cast call <rs> hasRole(bytes32,address) <DEFAULT_ADMIN_ROLE> <Safe>");
        }
        console2.log("================================================================");
    }
}
