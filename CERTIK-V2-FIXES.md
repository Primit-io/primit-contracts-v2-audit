# CertiK V2 Preliminary Findings · Fix Index + Mainnet Implementations

> **Prepared for**: CertiK (CertiK_Xuesong / `CertiK4Audit`)
> **Date**: 2026-08-27
> **Baseline commit** (private repo `primit-avax-contracts`): `d189854` — `chore: aggregate v2/certik-preliminary-fixes into main · full contract src + 24 CertiK fix (#28)`
> **Sync scope of this audit repo**: source of the 5 in-scope directories (`plp_contract` · `rebate_contract` · `referral_storage_contract` · `vault_contract` · `shared`) at that baseline. LT-migration work (`settleUserPnl` · added on top of PLP · 2026-08-26) is deliberately EXCLUDED from this sync — it is a new feature outside the CertiK V2 scope and is on a separate track.

---

## 1 · Fix Index (22 CertiK PRI-* findings addressed)

Each row: PRI-ID → fix commit → file(s) touched → nature. Rows 1-21 landed on the `v2/certik-preliminary-fixes` branch merged into `main` via PR #28 (baseline `d189854`). PRI-05 landed later — see the note in row 4 below.

| PRI | Commit | PR | File(s) | Nature |
|---|---|---|---|---|
| PRI-03 | `0cb3db8` | #4 | `plp_contract/src/LiquidityVault.sol` | fix · call `_disableInitializers()` in constructor to lock raw implementation |
| PRI-03 (script) | `75b8782` | #5 | `plp_contract/script/UpgradePlpImplAvax.s.sol` | UUPS upgrade script for PRI-03 |
| PRI-04 | `8cadfd7` | #6 | `vault_contract/src/contracts/core/vault/Vault.sol` (docs) | clarify `recordPositionClose` is audit-event only (no state change) |
| **PRI-05** | `58376fc` | primit-avax-contracts#32 | `plp_contract/src/LiquidityVault.sol` · `plp_contract/test/LiquidityVault.t.sol` | fix · add symmetric `unpause()` external onlyRole(ADMIN_ROLE) · 3 new TDD tests(admin unpause · non-admin revert · pause→unpause→deposit E2E). See §5 "PRI-05 deploy state" below — this fix has not yet been deployed to mainnet at time of sync; the audit repo source now matches the intended fix, mainnet upgrade is scheduled next. |
| PRI-06 | `ed36a8e` | #8 | `vault_contract/src/contracts/core/vault/Vault.sol` | add `onlyOwner` to `reinitializeSettlementCaps` |
| PRI-06 + PRI-10 (script) | `4cf148a` | #13 | `vault_contract/script/UpgradeVaultCertikBatchAvax.s.sol` | Vault UUPS batch upgrade for PRI-06 + PRI-10 |
| PRI-07 | `4c74fd2` | #9 | `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol` | cap debit to position-scoped obligation |
| PRI-08 (script) | `4035a24` | #10 | `referral_storage_contract/script/UpgradeReferralStorageAvax.s.sol` | ReferralStorage UUPS upgrade script |
| PRI-09 (script) | `86dfb44` | #11 | `rebate_contract/script/UpgradeRebateDistributorAvax.s.sol` | RebateDistributor UUPS upgrade script |
| PRI-10 | `3aa59ed` | #12 | `plp_contract/src/LiquidityVault.sol` | reject zero-address role holders in `initialize` |
| PRI-11 (v1) | `30c1962` | #14 | `vault_contract/src/contracts/core/vault/Vault.sol` | owner-gated `setPlpVaultAddress` (rotate-friendly setter · superseded — see PRI-11 (v2) below) |
| **PRI-11 (v2)** | `5184ee6` | primit-avax-contracts#33 | `vault_contract/src/contracts/core/vault/Vault.sol` · 9 test files · 3 deploy scripts | **complete initialize** · `initialize(InitParams)` sets all 5 previously-missing state variables (`plpVault` · `liquidationManager` · `protocolFeeRecipient` · `dailySettlementCreditCap` · `dailyUserSettlementCreditCap`) in one call per CertiK 08-28 request. `reinitializer(3/4/5)` and `setPlpVaultAddress` retained for legacy proxies and admin rotation. See §6 below for deploy state. |
| PRI-12 | `d1cbc0a` | #15 | `vault_contract/src/contracts/core/vault/Vault.sol` | add `withdrawAll` for dust escape |
| PRI-13 | `eb55ee3` | #16 | `vault_contract/src/contracts/core/vault/Vault.sol` | reject non-future `expiresAt` in `permitCloseOperator` |
| PRI-14 | `6ef312a` | #17 | `vault_contract/src/contracts/core/vault/Vault.sol` | remove stale `PositionBalanceSettled` emit on replay |
| PRI-15 | `3852b98` | #18 | `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol` (docs) | document precision on `PositionSnapshot` / `OraclePrice` / `_remainingCollateral` |
| PRI-16 | `efff0b8` | #19 | `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol` | reject stale `PositionSnapshot` at `liquidate` time |
| PRI-17 | `436eec7` | #20 | `referral_storage_contract/src/contracts/referral/ReferralStorage.sol` | `grantHandlerRole` / `revokeHandlerRole` use internal primitives |
| PRI-18 | `eb1138b` | #21 | `vault_contract/src/contracts/core/vault/Vault.sol` | remove dead code in `_setReferralCode` |
| PRI-19 | `a706083` | #22 | `shared/role/RoleStore.sol` | prune role from `_roles` when last member revoked |
| PRI-23 | `83789bf` | #24 | `vault_contract/src/contracts/core/vault/Vault.sol` (docs) | document `withdrawNonces` invalidation on settlement paths |
| PRI-24 | `5b07ca8` | #25 | `vault_contract/src/contracts/core/vault/Vault.sol` (docs) | document dual-key design of `params.closeId` |
| PRI-25 | `4cc04bc` | #26 | `vault_contract/src/contracts/core/vault/Vault.sol` (docs) | document distinct access models on the two settlement paths |

**Test coverage for the fixes** — every affected contract has an accompanying `CertiKFixes.t.sol` under its `test/` directory:
- `plp_contract/test/LiquidityVault.t.sol` (extended)
- `rebate_contract/test/CertiKFixes.t.sol`
- `referral_storage_contract/test/CertiKFixes.t.sol`
- `vault_contract/test/CertiKFixes.t.sol` · `VaultCriticalFixes.t.sol` · `VaultPLPAuthorization.t.sol` · `VaultPositionClosed.t.sol` · `VaultCloseOperatorPermit.t.sol` · `VaultLiquidationSettlement.t.sol` · `VaultAvaxChainId.t.sol`

---

## 2 · Mainnet Implementations (all Snowscan-verified · post-fix)

Each row is the current live impl on Avalanche C-Chain (chainId 43114). Every impl was verified on Snowscan at deploy time; click any link to see the flattened source and confirm bytecode ↔ source match. Ownership is EOA `0x2821c28b7A57c2E0537f5595e8e0eEAEC4b9F386` pending SAFE migration (see `AUDIT-INVENTORY.md §7`).

| # | Contract | Proxy | Latest Impl | Snowscan (Impl) | Upgrade tx (fix landed) |
|---|---|---|---|---|---|
| 1 | **Vault** | `0x0A30176bba21d262cDc652814b8C2A4c9a397b1b` | `0xfb4f9916a2bb07fb83d81a49221ea5ed63bc4889` (current live) | [verified](https://snowscan.xyz/address/0xfb4f9916a2bb07fb83d81a49221ea5ed63bc4889#code) | (superseded by later upgrade · see note below) |
| 1a | **Vault** — previous impl (superseded) | `0x0A30176bba21d262cDc652814b8C2A4c9a397b1b` | `0x181f6Bbf7D706cc2B1B14b03Bf86D7B773C2e92D` | [verified](https://snowscan.xyz/address/0x181f6Bbf7D706cc2B1B14b03Bf86D7B773C2e92D#code) | `0xf0a18b6511898c8c4f876acf6e4a9e68fcbcc4ae1fd2a4c65ba5b97ac5a2b697` (CertiK batch fix landing · then further upgraded) |
| 2 | **ReferralStorage** | `0x3953a15024c2F391733Bd614F0056f078Cd85199` | `0xF13B031b1A24942d43eE3d3C78A3e3e9667faB7b` | [verified](https://snowscan.xyz/address/0xF13B031b1A24942d43eE3d3C78A3e3e9667faB7b#code) | `0x72d90a8c5c6f4f9d6f273f2ca60241182598f882fd39618940262d9d8544c8b1` |
| 3 | **RebateDistributor** | `0xe2E0cF80E30f3988b2704DED5B0ED3A908083b90` | `0x30b08F944b4b0e8461b439A41bA0eC64DaDe2a9D` | [verified](https://snowscan.xyz/address/0x30b08F944b4b0e8461b439A41bA0eC64DaDe2a9D#code) | `0x7c14288f6a4fb8d4403163087efb1f5d86ad9d81cd9d762920355344a19acac6` |
| 4 | **LiquidationManager** | (direct · non-proxy) | `0x7F74d37C7c5853cFAe133A9Db120591170C4b7F5` | [verified](https://snowscan.xyz/address/0x7F74d37C7c5853cFAe133A9Db120591170C4b7F5#code) | Deploy: `0x045394a7827174f9e49a686f0892dffd5f8a0c8f544ff8e801f2bea69af4c12e` · Vault.setLiquidationManager: `0xd9f3034edb607e96d83d72cb3f2ff95dae49f21ac26c27df48658ad4963bb773` |
| 5 | **LiquidityVault (PLP)** — CertiK-scope impl | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` | *(PRI-03 impl · superseded on 2026-08-26 by an LT-feature upgrade; see note below)* | — | — |
| 5a | **LiquidityVault (PLP)** — current live impl | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` | `0x7eEC6049Bd502fE32eC2DE64E1f0F12d9d23B343` | [verified](https://snowscan.xyz/address/0x7eEC6049Bd502fE32eC2DE64E1f0F12d9d23B343#code) | `0x18b7ab7951956622dcccbf36c7f7c4cc35776a25f476330fd7dc64f6c56c944c` |
| 5b | **LiquidityVault (PLP)** — previous impl (superseded 2026-09-01) | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` | `0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe` | [verified](https://snowscan.xyz/address/0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe#code) | `0x7b75c7854882992cb64cae176a063254cb1a77938ef97526569d6ea85689bc85` |
| 6 | **BufferPool** | (direct · non-proxy) | `0x83710e300ec5a77c9252be4202f818ee1428d6da` | [verified](https://snowscan.xyz/address/0x83710e300ec5a77c9252be4202f818ee1428d6da#code) | (unchanged since original deploy) |
| 7 | **shared/** (libraries · RoleStore / Role / Price / Errors) | (linked · no proxy) | (embedded in dependents) | — | — |

### Note on row 5 vs 5a — PLP LiquidityVault

The current live impl `0x88F7AF…10DEe` (row 5a) contains **both** the CertiK PRI-03 fix (`_disableInitializers`) **and** a new `settleUserPnl(user, delta, nonce, deadline, sig)` function that was added on 2026-08-26 for the LiquidityTech backend integration (unrelated to CertiK V2 findings). This audit repo's `plp_contract/src/LiquidityVault.sol` reflects the **PRI-03 baseline only** (no `settleUserPnl`), matching what CertiK's V2 review covers.

If CertiK wants byte-for-byte review of the on-chain impl, the additional surface in `0x88F7AF…10DEe` beyond this repo's source is a single new external function (~30 LOC) plus its typehash + role constant + event + error. Full spec: `DESIGN-2026-0825-002-LT-Settlement-Contract-Signer-Path.md` in the `internal-docs` repo (available on request). This LT-scope surface is scheduled for its own audit pass separately from V2.

---

## 5 · PRI-05 status (as of 2026-09-01)

**Status: DEPLOYED — source and mainnet both contain the `unpause()` fix.**

### Source

`plp_contract/src/LiquidityVault.sol` has the symmetric `unpause() external onlyRole(ADMIN_ROLE)` (see Fix Index row above). LiquidityVault test suite: **55/55 green** (3 new PRI-05 tests: admin unpause · non-admin revert · pause→unpause→deposit E2E).

### Mainnet (Avalanche C-Chain · 43114)

Landed 2026-09-01 via UUPS upgrade. Proxy address unchanged (`0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7`) — user-facing address is stable across all impl upgrades.

| Item | Value |
|---|---|
| PLP Proxy | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` |
| **New impl** | `0x7eEC6049Bd502fE32eC2DE64E1f0F12d9d23B343` ([Snowscan · verified](https://snowscan.xyz/address/0x7eEC6049Bd502fE32eC2DE64E1f0F12d9d23B343#code)) |
| Previous impl (superseded) | `0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe` |
| Deploy tx (new impl) | [`0x393f6938…4bea`](https://snowscan.xyz/tx/0x393f6938259f7056599483303aae1d40dcd62cb9133f55ff136865b46a884bea) |
| UUPS upgrade tx | [`0x18b7ab79…944c`](https://snowscan.xyz/tx/0x18b7ab7951956622dcccbf36c7f7c4cc35776a25f476330fd7dc64f6c56c944c) |

### On-chain verification (post-upgrade)

- ERC1967 impl slot on proxy points at `0x7eEC6049…B343` ✅
- `eth_getCode(new impl)` grep · unpause selector `0x3f4ba83a` count = **1** ✅ (PRI-05 landed)
- `eth_getCode(new impl)` grep · pause selector `0x8456cb59` count = **1** ✅ (preserved)
- Bytecode size · new 20502 chars vs old 20242 chars (+260 for the added `unpause()` function · no regression)
- New impl carries both the PRI-05 unpause and the pre-existing `settleUserPnl` LT surface (source built from the same `LiquidityVault.sol` that contains both) — no LT feature regression

Fix summary now ready for CertiK review: **Pending → Resolved** requested. Alleviation update will reference the addresses and tx hashes in this section.

---

## 6 · PRI-11 status (as of 2026-09-01)

**Status: source landed. Mainnet upgrade optional.**

Per CertiK's 08-28 note, the expected fix is to add complete initialization logic to `initialize()` (so fresh deployments do not require a `reinitializer` chain). The v1 fix (owner-gated `setPlpVaultAddress`, PR #14) did not satisfy that expectation. The v2 fix (PR primit-avax-contracts#33 · commit `5184ee6`) implements it directly.

### Source

`vault_contract/src/contracts/core/vault/Vault.sol` now exposes:

```solidity
struct InitParams {
    address usdc;
    address backendSigner;
    address referralStorage;
    string  domainName;
    string  domainVersion;
    address owner;
    // PRI-11 additions:
    address plpVault;                    // required · non-zero
    address liquidationManager;          // required · non-zero
    address protocolFeeRecipient;        // required · non-zero
    uint256 dailySettlementCreditCap;    // may be 0 · admin sets later
    uint256 dailyUserSettlementCreditCap; // may be 0 · admin sets later
}

function initialize(InitParams memory p) external initializer { ... }
```

Vault test suite: **118/118 passing** (`forge test`), including 5 new PRI-11 tests in `test/CertiKFixes.t.sol`:

- `test_PRI11_initialize_sets_all_pri11_state_vars`
- `test_PRI11_initialize_reverts_when_plpVault_zero`
- `test_PRI11_initialize_reverts_when_liquidationManager_zero`
- `test_PRI11_initialize_reverts_when_protocolFeeRecipient_zero`
- `test_PRI11_initialize_allows_zero_caps`

The struct is used so `initialize` fits under Solc's stack-depth limit without turning on `via_ir` (which would change bytecode across every existing verified deployment).

### Retained (not removed)

Per CertiK 08-28 · "reinitialize can still be used for upgrade-time reinitialization":

- `reinitializer(3)` — `reinitializeSettlementCaps`
- `reinitializer(4)` — `reinitializeProtocolFees`
- `reinitializer(5)` — `reinitializeAddPLPAddress`
- `setPlpVaultAddress` — v1 rotate-friendly setter, still useful for admin rotation

### Mainnet

Current live Vault impl `0xfb4f9916a2bb07fb83d81a49221ea5ed63bc4889` (behind proxy `0x0A30176bba21d262cDc652814b8C2A4c9a397b1b`) still carries the old 6-parameter `initialize`. **PRI-11 does not require a mainnet upgrade to be considered fixed** — the finding is about *source* initialization completeness for future fresh deployments, and the current live proxy is already `_initialized == 5` with every required state variable populated via the v1 setter path.

A mainnet upgrade to the new impl is nevertheless a nice-to-have so that Snowscan's `initialize` signature matches this repo's source. If done, it uses `upgradeToAndCall(newImpl, "")` (empty init data because the proxy cannot re-initialize) and does not touch stored state.

This section will be updated with the new impl address + upgrade tx if/when that upgrade lands.

---

## 3 · How to reproduce the fix build

```bash
git clone https://github.com/Primit-io/primit-contracts-v2-audit.git
cd primit-contracts-v2-audit
# per-directory forge build (each in-scope dir is a self-contained Foundry project):
(cd vault_contract && forge test)
(cd plp_contract && forge test)
(cd rebate_contract && forge test)
(cd referral_storage_contract && forge test)
```

Compiler settings are pinned in each dir's `foundry.toml` — Solidity `0.8.20` · EVM `shanghai` · optimizer runs `200`. `plp_contract` uses `via_ir = true` (documented in `AUDIT-INVENTORY.md §2`).

---

## 4 · Contact

**Engineering lead**: Lee (`tech@primit.io`)
For any clarification on a specific PRI-* fix or a request to look at the LT settlement path separately, please ping directly.
