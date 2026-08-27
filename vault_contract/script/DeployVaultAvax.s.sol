// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @title DeployVaultAvax
/// @notice One-shot deploy of the Primit Vault UUPS proxy on AVAX C-Chain
///         (mainnet 43114) or Fuji testnet (43113).
///
/// Design reference: `internal-docs/DESIGN-2026-0512-001-AVAX-Vault-Settlement.md`
///                   §3.4 + §3.5.
///
/// Hard pre-conditions enforced inside the script:
///   1. `block.chainid` MUST be 43113 (Fuji) or 43114 (AVAX mainnet).
///      Refuses Arb / Sepolia / Ethereum / unknown chains.
///   2. SEC-2026-0428-002 interlock: `_backendSigner` MUST NOT equal the
///      leaked ADMIN address 0xaDff12DfE7c8992F9e97083838273a20B3B44e40
///      (lowercased compared). Any reuse of the leaked key aborts deploy.
///   3. Required env vars present: USDC_ADDRESS, BACKEND_SIGNER,
///      REFERRAL_STORAGE, ADMIN, PRIVATE_KEY.
///   4. (Mainnet only, optional) SAFE_OWNER_ADDR — if set, the deploy
///      transferOwnership(SAFE_OWNER_ADDR) in the SAME broadcast batch
///      so no EOA single-point window exists.
///
/// What the script does (single broadcast block):
///   1. Validate chain-id + SEC-002 interlock on the backendSigner.
///   2. Deploy Vault implementation contract.
///   3. Deploy ERC1967Proxy pointing at the impl, with `initialize(...)`
///      call encoded into the constructor (same tx as proxy deploy).
///   4. (Optional) transferOwnership(SAFE) if SAFE_OWNER_ADDR is provided.
///   5. Console-log every address + chainid + domain string for direct
///      paste into deployments/fuji.json or deployments/mainnet.json.
///
/// Run (Fuji):
///     export PRIVATE_KEY=<Fuji deployer key,非 SEC-002 leaked>
///     export USDC_ADDRESS=0x289a53c680dD1162cD792101Fff5352728C6Fa41   # MockUSDCe Fuji
///     export BACKEND_SIGNER=<Fuji test backend signer EOA>
///     export REFERRAL_STORAGE=<Fuji ReferralStorage 部署后地址>
///     export ADMIN=<Fuji deployer EOA — 后续 Safe 接管前临时 owner>
///     forge script script/DeployVaultAvax.s.sol:DeployVaultAvax \
///       --rpc-url https://api.avax-test.network/ext/bc/C/rpc \
///       --broadcast --slow --verify --etherscan-api-key $SNOWTRACE_API_KEY
///
/// Run (Mainnet — requires AWS KMS-issued backend signer + Safe接管):
///     export PRIVATE_KEY=<KMS-issued mainnet deployer,非 SEC-002 leaked>
///     export USDC_ADDRESS=0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7   # USDC.e mainnet
///     export BACKEND_SIGNER=<KMS-issued mainnet backend signer EOA>
///     export REFERRAL_STORAGE=<Mainnet ReferralStorage 地址>
///     export ADMIN=<KMS deployer (临时,立即 transferOwnership 到 Safe)>
///     export SAFE_OWNER_ADDR=<Mainnet Safe 3-of-5 地址>   # 必填(mainnet)
///     forge script script/DeployVaultAvax.s.sol:DeployVaultAvax \
///       --rpc-url https://api.avax.network/ext/bc/C/rpc \
///       --broadcast --slow --verify --etherscan-api-key $SNOWTRACE_API_KEY
contract DeployVaultAvax is Script {
    /// SEC-2026-0428-002 leaked ADMIN address (lowercase).
    /// Hard-coded so the script refuses any value matching this regardless of env.
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;

    /// D7 (2026-07-24) known-compromised admins: private keys ported into the
    /// dev environment for H1 upgrades. Treat as burned for any V2 deploy.
    address constant KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c96A7118d879Cf3a9e39bdC4Ee1D1b4D8;
    address constant KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2402807C183dD25E68AEE3f0Cc4BA;

    /// Native USDC on Avalanche C-Chain (Circle official). V2 accepts USDC only.
    address constant EXPECTED_USDC_MAINNET = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    uint256 constant FUJI_CHAINID = 43_113;
    uint256 constant AVAX_MAINNET_CHAINID = 43_114;

    function run() external returns (Vault vault) {
        uint256 chainId = block.chainid;
        require(
            chainId == FUJI_CHAINID || chainId == AVAX_MAINNET_CHAINID,
            "DeployVaultAvax: must run on AVAX 43113 (Fuji) or 43114 (mainnet)"
        );

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        address referralStorage = vm.envAddress("REFERRAL_STORAGE");
        // ADMIN env is optional; used as the initial owner only on Fuji where
        // Safe is not yet deployed. On mainnet, initial owner is forced to be
        // the deployer so transferOwnership(Safe) can succeed in the same batch.
        address adminEnv;
        try vm.envAddress("ADMIN") returns (address a) {
            adminEnv = a;
        } catch {
            adminEnv = address(0);
        }

        // SEC-2026-0428-002 interlock: refuse leaked ADMIN as any role
        require(
            deployer != LEAKED_ADMIN,
            "DeployVaultAvax: SEC-002 violation - deployer == leaked ADMIN"
        );
        require(
            backendSigner != LEAKED_ADMIN,
            "DeployVaultAvax: SEC-002 violation - backendSigner == leaked ADMIN"
        );
        require(
            adminEnv != LEAKED_ADMIN,
            "DeployVaultAvax: SEC-002 violation - admin == leaked ADMIN"
        );

        // D7 (2026-07-24): refuse any role == known-compromised admin
        require(
            deployer != KNOWN_COMPROMISED_ADMIN_1 && deployer != KNOWN_COMPROMISED_ADMIN_2,
            "DeployVaultAvax: D7 SEC - deployer == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            backendSigner != KNOWN_COMPROMISED_ADMIN_1 && backendSigner != KNOWN_COMPROMISED_ADMIN_2,
            "DeployVaultAvax: D7 SEC - backendSigner == KNOWN_COMPROMISED_ADMIN"
        );
        require(
            adminEnv != KNOWN_COMPROMISED_ADMIN_1 && adminEnv != KNOWN_COMPROMISED_ADMIN_2,
            "DeployVaultAvax: D7 SEC - admin == KNOWN_COMPROMISED_ADMIN"
        );

        // V2 (2026-07-24): mainnet USDC hard-lock. Fuji free (test USDC allowed).
        if (chainId == AVAX_MAINNET_CHAINID) {
            require(usdc == EXPECTED_USDC_MAINNET, "DeployVaultAvax: mainnet must use native USDC 0xB97EF9EF");
        }

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
                require(allowEoa, "DeployVaultAvax: mainnet requires SAFE_OWNER_ADDR OR ALLOW_MAINNET_EOA_OWNER=true");
            }
            if (safeOwner != address(0)) {
                require(
                    safeOwner != LEAKED_ADMIN,
                    "DeployVaultAvax: SAFE_OWNER_ADDR invalid"
                );
            }
        }

        // Initial owner selection:
        //   - When SAFE_OWNER_ADDR is set (mainnet path): initial owner MUST
        //     be the deployer so transferOwnership(Safe) succeeds in the same
        //     batch (no EOA single-point window). ADMIN env is ignored.
        //   - When SAFE_OWNER_ADDR is unset (Fuji testing): initial owner is
        //     ADMIN env value, allowing flexible test setup.
        address initialOwner;
        if (safeOwner != address(0)) {
            initialOwner = deployer;
        } else {
            require(adminEnv != address(0), "DeployVaultAvax: ADMIN env required when SAFE_OWNER_ADDR unset (Fuji path)");
            initialOwner = adminEnv;
        }

        string memory domainName = chainId == AVAX_MAINNET_CHAINID
            ? "Primit Vault AVAX"
            : "Primit Vault AVAX Fuji";
        string memory domainVersion = "1.0.0";

        console2.log("================================================================");
        console2.log("  DeployVaultAvax - AVAX C-Chain or Fuji");
        console2.log("================================================================");
        console2.log("  chainid          :", chainId);
        console2.log("  network          :", chainId == AVAX_MAINNET_CHAINID ? "AVAX mainnet" : "AVAX Fuji");
        console2.log("  deployer (msg)   :", deployer);
        console2.log("  usdc (USDC.e)    :", usdc);
        console2.log("  backendSigner    :", backendSigner);
        console2.log("  referralStorage  :", referralStorage);
        console2.log("  initialOwner     :", initialOwner);
        console2.log("  ADMIN env        :", adminEnv);
        console2.log("  safeOwner (final):", safeOwner);
        console2.log("  domainName       :", domainName);
        console2.log("  domainVersion    :", domainVersion);
        console2.log("");

        vm.startBroadcast(deployerPk);

        // Step 1: deploy Vault implementation
        Vault implementation = new Vault();
        console2.log("[1/3] Vault implementation:", address(implementation));

        // Step 2: deploy proxy with initialize call (same tx)
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                Vault.initialize,
                (usdc, backendSigner, referralStorage, domainName, domainVersion, initialOwner)
            )
        );
        vault = Vault(address(proxy));
        console2.log("[2/3] Vault proxy        :", address(vault));

        // Step 3: if mainnet, immediately transferOwnership to the Safe in the
        // SAME broadcast batch. There is no EOA single-point ownership window.
        if (safeOwner != address(0)) {
            vault.transferOwnership(safeOwner);
            console2.log("[3/3] Vault.owner ->     :", safeOwner);
            require(
                vault.owner() == safeOwner,
                "DeployVaultAvax: post-condition transferOwnership failed"
            );
        } else {
            console2.log("[3/3] Vault.owner kept   :", initialOwner, "(Fuji - Safe takeover in Phase 2)");
        }

        vm.stopBroadcast();

        // Post-flight sanity reads
        console2.log("");
        console2.log("  -- post-deploy sanity --");
        console2.log("  vault.usdc()       :", address(vault.usdc()));
        console2.log("  vault.backendSigner:", vault.backendSigner());
        console2.log("  vault.owner()      :", vault.owner());
        console2.log("  vault.totalDeposits:", vault.totalDeposits());
        console2.log("");
        console2.log("================================================================");
        console2.log("  DEPLOY COMPLETE");
        console2.log("");
        console2.log("  Next:");
        if (chainId == FUJI_CHAINID) {
            console2.log("    1. Add address to deployments/fuji.json");
            console2.log("    2. Phase 2: Safe + Timelock takeover (DESIGN doc Phase 2)");
        } else {
            console2.log("    1. Add address to deployments/mainnet.json");
            console2.log("    2. Verify Safe is owner: cast call <vault> owner() == <Safe>");
            console2.log("    3. Backend wire: set AVAX_VAULT_ADDRESS env on primit-avax-backend");
            console2.log("    4. G-AVAX-4 reconciler 7-day window starts now");
        }
        console2.log("================================================================");
    }
}
