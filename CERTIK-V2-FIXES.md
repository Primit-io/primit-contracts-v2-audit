# CertiK V2 Findings · Fix Index + Alleviations + Mainnet Implementations

> **Prepared for**: CertiK (CertiK_Xuesong / `CertiK4Audit`)
> **Date**: 2026-08-27 · **Refreshed**: 2026-09-08 (post-final-delivery sync)
> **Final report**: [`docs/audit/CertiK-REP-Primit-2-final-2026-09-03.pdf`](./docs/audit/CertiK-REP-Primit-2-final-2026-09-03.pdf) · audited commits `55b9fec4…`, `7c98edf9…`, `c8253041…` (this repo's `main` HEAD at delivery time)
> **Delivery totals**: 26 findings · 18 Resolved · 7 Acknowledged · 1 Optimization · 0 Critical/Major · 0 Partially Resolved · 0 Declined
> **Baseline commit** (private repo `primit-avax-contracts`): `d189854` — `chore: aggregate v2/certik-preliminary-fixes into main · full contract src + 24 CertiK fix (#28)`
> **Sync scope of this audit repo**: source of the 5 in-scope directories (`plp_contract` · `rebate_contract` · `referral_storage_contract` · `vault_contract` · `shared`) at that baseline. LT-migration work (`settleUserPnl` · added on top of PLP · 2026-08-26) is deliberately EXCLUDED from this sync — it is a new feature outside the CertiK V2 scope and is on a separate track.

---

## 1 · Fix Index (26 CertiK findings tracked)

### 1a · Severity / Status Summary (all 26)

Compact one-line-per-finding view; every row links to the verbatim Alleviation in §7.

| PRI | Severity | Final status | Repo action |
|---|---|---|---|
| [PRI-01](#pri-01--centralization-related-risks) | Centralization | Acknowledged | no code · Safe+Timelock governance migration scheduled (see §7) |
| [PRI-02](#pri-02--centralized-control-of-contract-upgrade) | Centralization | Acknowledged | no code · same Safe+Timelock migration as PRI-01 |
| [PRI-03](#pri-03--unprotected-upgradeable-contract) | Medium | ✅ Resolved | `_disableInitializers()` in constructor · row in §1b |
| [PRI-04](#pri-04--fund-risks-caused-by-insufficient-funds-and-backendsigner) | Medium | Acknowledged | docs · natspec added on `recordPositionClose` semantics · row in §1b |
| [PRI-05](#pri-05--missing-unpause-leaves-plp-permanently-pausable-only) | Medium | ✅ Resolved | `unpause()` added · deployed 2026-09-01 · see §5 |
| [PRI-06](#pri-06--reinitializesettlementcaps-missing-onlyowner-modifier) | Medium | ✅ Resolved | `onlyOwner` on `reinitializeSettlementCaps` · row in §1b |
| [PRI-07](#pri-07--negative-remaining-clears-the-users-entire-shared-vault-balance) | Medium | ✅ Resolved | position-scoped `obligation = fee + max(0, -remaining)` · row in §1b |
| [PRI-08](#pri-08--missing-tier-initialization-validation-leads-to-silent-rebate-disablement) | Minor | ✅ Resolved | `_tierInitialized` check · row in §1b |
| [PRI-09](#pri-09--missing-duplicate-recipient-validation-leads-to-repeated-rebate-distribution) | Minor | ✅ Resolved | ascending-order guard on recipients · row in §1b |
| [PRI-10](#pri-10--missing-zero-address-validation) | Minor | ✅ Resolved | zero-address rejection · row in §1b |
| [PRI-11](#pri-11--incomplete-initialize-forces-mandatory-post-deploy-reinitializer-calls) | Minor | ✅ Resolved | complete `initialize(InitParams)` · see §6 |
| [PRI-12](#pri-12--minwithdraw-prevents-users-from-fully-draining-their-vault-balance) | Minor | ✅ Resolved | `withdrawAll()` · row in §1b |
| [PRI-13](#pri-13--permitcloseoperator-does-not-validate-that-expiresat-is-in-the-future) | Minor | ✅ Resolved | `expiresAt` future-check · row in §1b |
| [PRI-14](#pri-14--issue-when-usedpositionbalancesettlements-is-already-consumed) | Minor | ✅ Resolved | remove stale `PositionBalanceSettled` emit · row in §1b |
| [PRI-15](#pri-15--undocumented-calculation-precision-in-remainingcollateral) | Minor | ✅ Resolved | precision natspec · row in §1b |
| [PRI-16](#pri-16--stale-positionsnapshot-has-no-expiry-before-liquidation) | Minor | ✅ Resolved | `maxSnapshotAge` check in `liquidate` · row in §1b |
| [PRI-17](#pri-17--granthandlerrole--revokehandlerrole-incompatible-with-adminrole-only-callers) | Minor | ✅ Resolved | switch to `_grantRole/_revokeRole` internals · row in §1b |
| [PRI-18](#pri-18--redundant-code-components) | Informational | ✅ Resolved | remove dead code in `_setReferralCode` · row in §1b |
| [PRI-19](#pri-19--stale-role-entries-remain-in-roles-after-last-member-is-revoked) | Informational | ✅ Resolved | prune role from `_roles` · row in §1b |
| [PRI-20](#pri-20--concerns-regarding-the-vaults-on-chain-state) | Informational | ✅ Resolved | no code · design confirmed intentional (§7) · CertiK accepted response |
| [PRI-21](#pri-21--recordpositionclosefor-requires-self-authorization-via-permitcloseoperator) | Optimization | Acknowledged | code on `v2/certik-preliminary-fixes` branch (PR #23) · mainnet deploy deferred |
| [PRI-22](#pri-22--confirmation-on-incomplete-liquidityvault) | Informational | Acknowledged | no code · v1 share-only design + no-nonce-bump on PLP transfers confirmed intentional (§7) |
| [PRI-23](#pri-23--settlepositionbalance-unexpectedly-invalidates-pending-withdraw-signatures) | Minor | Acknowledged | natspec added on `settlePositionBalance/settleLiquidation` (PR #24) · row in §1b |
| [PRI-24](#pri-24--confirmation-on-paramscloseid-in-recordpositioncloseandsettlefor) | Informational | Acknowledged | dual-key-design natspec (PR #25) · row in §1b |
| [PRI-25](#pri-25--confirmation-on-access-control-for-settlepositionbalance-calls) | Informational | Acknowledged | dual-access-model natspec (PR #26) · row in §1b |
| [PRI-26](#pri-26--confirmation-on-fee-and-maintenance-margin) | Minor | ✅ Resolved | on-chain fee/margin bounds · 13 new tests · vault_contract 108/108 pass · row in §1b |

### 1b · Fix commit index (per-commit view)

Rows for PRI-03..PRI-25 landed on the `v2/certik-preliminary-fixes` branch merged into `main` via PR #28 (baseline `d189854`). PRI-05 and PRI-11(v2) landed later — see §5 / §6 below. **PRI-21 and PRI-26 code** landed on the same branch (PR #23 and PR #27 respectively) and are documented here for completeness; both are pending the next canonical mainnet release for deploy.

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
| **PRI-21** | (branch `v2/certik-preliminary-fixes`) | primit-avax-contracts#23 | `vault_contract/src/contracts/core/vault/Vault.sol` · `vault_contract/test/VaultCloseOperatorPermit.t.sol` | skip `closeOperatorApprovalExpiries` check when `msg.sender == user` on `recordPositionCloseFor` / `_recordPositionCloseAndSettleFor` · vault_contract 98/98 pass · mainnet deploy deferred pending canonical release |
| **PRI-26** | (branch `v2/certik-preliminary-fixes`) | primit-avax-contracts#27 | `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol` · `vault_contract/src/contracts/core/vault/Vault.sol` · `vault_contract/test/CertiKFixes.t.sol` · `vault_contract/test/LiquidationManager.t.sol` | on-chain bounds · LM `maxLiquidationFeeRate` (default 5%) · LM `min/maxMaintenanceMarginRate` (0.1% / 50%) · Vault `maxProtocolFeeAmount` (opt-in cap) · owner-only setters reject zero/invert · storage layout `__gap` 31→30 · 13 new tests · vault_contract 108/108 pass · mainnet deploy deferred pending canonical release |

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

---

## 7 · Full CertiK Alleviations (verbatim, all 26 findings)

Verbatim client-side responses as printed in the CertiK final report ([`docs/audit/CertiK-REP-Primit-2-final-2026-09-03.pdf`](./docs/audit/CertiK-REP-Primit-2-final-2026-09-03.pdf)). Each block reproduces the `[Primit 2, MM/DD/2026]` reply that CertiK accepted; multiple stacked replies on the same finding indicate iterative rounds of the audit. No paraphrase.

### PRI-01 · Centralization Related Risks

- **Severity**: Centralization · **Final status**: Acknowledged
- **Location**: n/a (multiple contracts, privileged-role enumeration across BufferPool/LiquidityVault/RebateDistributor/ReferralStorage/RoleStore/LiquidationManager/Vault)

> [Primit 2, 08/21/2026]: Status: Acknowledged.
> We acknowledge CertiK's enumeration of privileged roles across the seven contracts (BufferPool, LiquidityVault, RebateDistributor, ReferralStorage, RoleStore, LiquidationManager, Vault) and confirm the described attack surface is accurate as of the audited commit `55b9fec4b3b553dc3d4b875dbc539ece55bb7e60`.
> We are proceeding with CertiK's recommended short-term remediation Gnosis Safe (3-of-5 multi-signature) plus TimelockController (48-hour delay) across all seven privileged roles with estimated delivery within four weeks of this response. Concrete scheduled steps: (1) deploy Gnosis Safe on Avalanche C-Chain with five signers; (2) deploy TimelockController with `proposer=Safe`, `executor=Safe`, `delay=48h`; (3) rotate `owner` / `DEFAULT_ADMIN_ROLE` on all seven in-scope contracts to the Timelock, retaining a separate `PAUSE_GUARDIAN` role held by the Safe directly (bypassing Timelock) for incident response; (4) rotate the five signer accounts (`backendSigner` instances on Vault / RebateDistributor / LiquidationManager, plus `oracleSigner` and `SIGNER_ROLE`) to Safe-controlled hot wallets, per our prior architecture decision record (ADR-2026-0428-002); (5) publish a public disclosure post listing the Timelock address, Safe address, obfuscated signer roster, and upgrade governance flow.
> Once the migration is complete, we will update this finding to Partially Resolved and share the deployed Timelock address, Gnosis Safe address, and the accompanying medium/blog link. A DAO/governance module is on our long-term roadmap and will be introduced after the protocol matures and community stewardship is in place; we do not intend to renounce ownership permanently, as the ability to upgrade the contracts is required to respond to future audit findings.

### PRI-02 · Centralized Control Of Contract Upgrade

- **Severity**: Centralization · **Final status**: Acknowledged
- **Location**: `plp_contract/src/LiquidityVault.sol:124` · `rebate_contract/src/contracts/core/referral/RebateDistributor.sol:371~373` · `referral_storage_contract/src/contracts/referral/ReferralStorage.sol:292~294` · `vault_contract/src/contracts/core/vault/Vault.sol:1006~1008`

> [Primit 2, 08/21/2026]: Status: Acknowledged.
> We acknowledge that the upgrade authority on the four in-scope proxy contracts (LiquidityVault `ADMIN_ROLE`, RebateDistributor `owner`, ReferralStorage `DEFAULT_ADMIN_ROLE`, Vault `owner`) is currently held by an EOA-controlled account, and that this represents a single point of failure.
> This finding is a subset of the broader centralization concern already addressed in our response to PRI-01: the same Gnosis Safe (3-of-5 multi-signature) plus TimelockController (48-hour delay) governance stack scheduled for delivery within four weeks will take ownership of these four proxies, gating every future `upgradeToAndCall` call through the 48-hour Timelock queue and requiring multi-signature approval on the Safe.
> Concrete additional steps specific to this finding: (1) after Timelock deployment, transfer or grant the upgrade authority on each of the four proxies (LiquidityVault `ADMIN_ROLE`, RebateDistributor `owner`, ReferralStorage `DEFAULT_ADMIN_ROLE`, Vault `owner`) to the Timelock address; (2) revoke the previous EOA holder from the upgrade role in the same transaction batch; (3) advance-notify the community via the same medium/blog post prior to any subsequent implementation migration. Once the migration is complete, we will update this finding to Partially Resolved and share the deployed Timelock address, Gnosis Safe address, and the accompanying medium/blog link. As with PRI-01, a DAO/governance module for upgrade control is on our long-term roadmap; we do not intend to renounce upgrade ownership permanently, as the ability to migrate implementations is required to respond to future audit findings and to ship the remaining fixes listed in this same report.

### PRI-03 · Unprotected Upgradeable Contract

- **Severity**: Medium · **Final status**: Resolved
- **Location**: `plp_contract/src/LiquidityVault.sol:100`

> [Primit 2, 08/27/2026]: The team heeded the advice and resolved the issue by adding `_disableInitializers()` in `contstructor()` in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-04 · Fund Risks Caused By Insufficient Funds And `backendSigner`

- **Severity**: Medium · **Final status**: Acknowledged
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:305~309, 472~483, 762~769, 979~986`

> [Primit 2, 08/21/2026]: Status: Acknowledged.
> This finding bundles four distinct sub-issues; we agree with the enumeration and address each below.
>
> (1) `emergencyWithdraw()`: the concern is a specific instance of the general privileged-role centralization we already track under PRI-01 and PRI-02. We are keeping `emergencyWithdraw()` as a catastrophic escape hatch (critical bug, oracle failure, chain incident) but the `owner` role that gates it is being migrated to a Gnosis Safe (3-of-5 multi-signature) plus TimelockController (48-hour delay), so any invocation of `emergencyWithdraw()` after the migration requires Safe quorum and 48-hour on-chain notice, with the pause/unpause path kept as a separate `PAUSE_GUARDIAN` role held by the Safe directly (Safe-only, no timelock) for incident response. Concrete progress under PRI-01/02: target four-week delivery, with the deployed Timelock and Safe addresses shared once the migration is complete.
>
> (2) `withdraw()` dependency on `backendSigner`: we acknowledge the liveness single-point-of-failure. The signature check is intended (it enforces a strict backend-side authorization cap on how much a user can withdraw at any moment, so that a user cannot front-run pending settlement or liquidation with a raw `withdraw` call), but signer unavailability would strand user funds. Current mitigations: (a) `emergencyWithdraw()` lets the owner rescue funds under a pause during a signer outage, (b) `permitCloseOperator()` lets a user delegate close-and-settle to an alternate operator, reducing dependency on a single hot signer, and (c) the backend signer key is deployed on a Safe-controlled hot wallet with a documented rotation runbook. Long-term hardening on our roadmap: a signer-less exit route that allows a user to submit an on-chain withdraw request during pause, wait a fixed delay window (e.g. 72 hours) with no backend counter-signature, and then self-execute; this will be tracked as a separate ticket and delivered in a follow-up release, at which point we will move this sub-issue to Partially Resolved.
>
> (3) `settlePositionBalance()` and `recordPositionCloseAndSettleFor()` modifying balances without token flow: this is the intended design of a CEX-style collateral ledger, and mirrors the same accounting model used by GMX v2, dYdX v4, and Hyperliquid. Token transfers only occur on `deposit()` and `withdraw()`; intra-position PnL, funding, and liquidation settlements move the internal `_balances` ledger only, and the pooled collateral in the Vault is sized to always back the aggregate credited balance. Replay is prevented by `usedPositionBalanceSettlements[settlementKey]` on `settlePositionBalance()` and by `usedCloseIds[closeId]` on `recordPositionCloseAndSettleFor()`. Additional on-chain safety rails already in the code: `type(int256).min` is explicitly rejected, negative deltas are truncated to the current chain balance so a loss on a zero-balance account settles cleanly at zero rather than underflowing, and positive deltas pass through `_consumeSettlementCreditCap(user, credit)` which enforces a per-user rate-limit on credited amounts.
>
> (4) `recordPositionClose()` replayability: intended by design. This function is a pure audit-event emitter (only `emit PositionClosed(…)`; no state mutation, no `_balances` write, no `_settlePositionBalance` call), so a replay produces a duplicate off-chain event but has no on-chain effect on user balances or system solvency. The signature carries a `deadline` which bounds the replay window, and our off-chain indexers already deduplicate by the `(positionId, closedAt)` tuple. `recordPositionCloseFor()` and `recordPositionCloseAndSettleFor()` do mutate state, remain replay-protected by `usedCloseIds[closeId]`. This design contract is now explicit in the natspec: see <https://github.com/Primit-io/primit-avax-contracts/pull/6> which adds a dedicated dev-note on `recordPositionClose` stating that duplicate emissions are permitted, that off-chain consumers must deduplicate by `(positionId, closedAt)`, and that callers needing replay-guarded record-and-settle semantics should use `recordPositionCloseFor` or `recordPositionCloseAndSettleFor`.

### PRI-05 · Missing `unpause()` Leaves PLP Permanently Pausable-Only

- **Severity**: Medium · **Final status**: Resolved
- **Location**: `plp_contract/src/LiquidityVault.sol:208~210`

> [Primit 2, 09/03/2026]: The team heeded the advice and resolved the issue by adding a corresponding `unpause()` function in commit `c8253041c00a4f38881d55c0d121bad5842a8026`

See also §5 for the mainnet upgrade addresses and transaction hashes.

### PRI-06 · `reinitializeSettlementCaps` Missing `onlyOwner` Modifier

- **Severity**: Medium · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:231~236`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding `onlyOwner` to `reinitializeSettlementCaps` in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-07 · Negative `remaining` Clears The User's Entire Shared Vault Balance

- **Severity**: Medium · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol:198~204` · `vault_contract/src/contracts/core/vault/Vault.sol:450~451`

> [Primit 2, 08/21/2026]: Status: Resolved.
> Fixed in PR <https://github.com/Primit-io/primit-avax-contracts/pull/9> and deployed to Avalanche mainnet at block `93328756`. Root fix (LiquidationManager side; Vault ABI unchanged): the liquidation obligation is now computed on-chain as position-scoped, `obligation = liquidationFee + max(0, -remaining)`, and `LiquidationManager.liquidate` now always passes `clearBalance=false` to `Vault.settleLiquidation`. Vault-side behaviour on `clearBalance=false` is exactly `min(obligation, balance)`, so the user's shared `_balances` is capped to the position's fee-plus-shortfall obligation and the remainder (unrelated deposits, PLP credits, other open positions' collateral) is preserved. If obligation exceeds the debited amount, the residue is surfaced explicitly through a new event `LiquidationBadDebt(bytes32 indexed positionId, bytes32 indexed liquidationKey, address indexed user, uint256 obligation, uint256 debitedAmount, uint256 badDebt)` for off-chain bad-debt accounting, exactly as recommended.
>
> TDD coverage in the same PR: three new Foundry tests assert that a liquidation with `remaining=-10` and `balance=1000` debits exactly `15` (fee=5 + shortfall=10) and leaves `985` preserved, that a liquidation whose obligation exceeds the available balance debits only the balance and emits `LiquidationBadDebt` with the correct obligation and residue, and a dedicated no-full-sweep regression guard asserts the leftover balance stays above 900 either and the settlement recipient never receives more than ~20 after the fix. Full `vault_contract` Foundry suite: 74 of 74 tests pass.
>
> Mainnet rollout: because LiquidationManager is a direct (non-proxy) contract, remediation was done by redeploying LiquidationManager and rewiring the Vault via `Vault.setLiquidationManager` in the same atomic broadcast (Vault upgrade was not required and was not performed). New LiquidationManager address: `0xb3a280809Bc29e010C67B45d49429B7b8fFF27E5`. Previous LiquidationManager (now severed from the Vault): `0xceb119aadd56b2fe602b634d50c40af21e985de1`. Vault proxy address is unchanged at `0xdf19d902fcb6295366a06620f76dcb49e686c403`. Broadcast transactions: LiquidationManager deploy `0x05ef970c30e9502a486a1f368b8d65a22f49ec1955e99cf07cb8dbb57c67f3d0`, Vault.setLiquidationManager `0x62bf11b522ffb045fe07f804a5fdfac504213664dcd28f251bbc18f4607ac3b7`, LiquidationManager.setKeeper `0x13346b274078bf6e2080c1893096e7e87c98e8edd976f09188bf6f48ca253e79`. Source code is verified on Routescan (Snowtrace).
>
> Post-upgrade on-chain verification: `Vault.liquidationManager()` reads the new LM address, and the new LM's `vault`, `backendSigner`, `oracleSigner`, `settlementRecipient`, `owner` and `keepers(backendSignerAddress)` all match the previous manager's parameters (no operational drift). Legacy note: the previous LiquidationManager at `0xceb119...` has never emitted a `LiquidationExecuted` event across the entire V2 mainnet lifetime (3 million blocks / roughly 70 days scanned), so no historical liquidations existed and the manager replacement carried zero legacy-state migration risk.
>
> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by deducting only the liquidation fee and the shortfall when `remaining` is negative, i.e., `liquidationFee + max(0, -remaining)`, instead of clearing the user's entire balance in the vault in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-08 · Missing Tier Initialization Validation Leads To Silent Rebate Disablement

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `referral_storage_contract/src/contracts/referral/ReferralStorage.sol:156~165`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding `_tierInitialized[_tierId]` check in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-09 · Missing Duplicate Recipient Validation Leads To Repeated Rebate Distribution

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `rebate_contract/src/contracts/core/referral/RebateDistributor.sol:237~249`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding a check in the `for` loop to ensure that user addresses are in ascending order in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-10 · Missing Zero Address Validation

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `plp_contract/src/LiquidityVault.sol:103~105` · `rebate_contract/src/contracts/core/referral/RebateDistributor.sol:268~270` · `vault_contract/src/contracts/core/vault/Vault.sol:843~845, 871~874`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding zero-address validation in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-11 · Incomplete `initialize()` Forces Mandatory Post-Deploy `reinitializer` Calls

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:180~215, 871~874`

> [Primit 2, 09/03/2026]: The project team resolved this issue by initializing the corresponding state variables and addresses in `initialize()` in commit `c8253041c00a4f38881d55c0d121bad5842a8026`
> Although the current implementation does not present an issue, we would still like to remind the project team that initializing `liquidationManager` in `initialize()` results in a non-standard deployment sequence for deployments (as opposed to upgrades), because `liquidationManager` requires the vault address to be set in its constructor.
> If the vault and `liquidationManager` need to be redeployed, the vault proxy must first be deployed. The vault proxy address should then be provided as the constructor argument when deploying `liquidationManager`. Finally, the vault's `initialize()` function should be called with the deployed `liquidationManager` address as an input.

See also §6 for the source-level details of the complete `initialize(InitParams)` fix.

### PRI-12 · `minWithdraw` Prevents Users From Fully Draining Their Vault Balance

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:296~298`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding `withdrawAll()` function in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-13 · `permitCloseOperator()` Does Not Validate That `expiresAt` Is In The Future

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:665~689`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding an `expiresAt` check in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-14 · Issue When `usedPositionBalanceSettlements` Is Already Consumed

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:808~817`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by removing the `PositionBalanceSettled` emit in this branch in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`.
> In addition, regarding the issue that "when `usedPositionBalanceSettlements` has already been consumed, `_transferProtocolFees` is skipped," the team confirmed that this is the intended design.

### PRI-15 · Undocumented Calculation Precision In `_remainingCollateral`

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol:255~262`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding the corresponding precise conventions to the NatSpec in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`.

### PRI-16 · Stale `PositionSnapshot` Has No Expiry Before Liquidation

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol:147~164`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding `maxSnapshotAge` check in `liquidate()` in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-17 · `grantHandlerRole` / `revokeHandlerRole` Incompatible With `ADMIN_ROLE`-Only Callers

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `referral_storage_contract/src/contracts/referral/ReferralStorage.sol:85~86, 187~198`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by replacing `grantRole` / `revokeRole` with `_grantRole` / `_revokeRole` inside the wrapper functions in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-18 · Redundant Code Components

- **Severity**: Informational · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:561, 570~571`

> [Primit 2, 08/28/2026]: Status: Acknowledged.
> We agree with the finding. Code cleanup landed in PR <https://github.com/Primit-io/primit-avax-contracts/pull/21> on the `v2/certik-preliminary-fixes` branch. The three redundant statements identified by CertiK are removed: the `private constant _VAULT_VERSION = 0x56415556` (a `"VAUV"` ASCII deployment marker that was never read anywhere on the contract surface), the local `uint256 _v = _VAULT_VERSION` at the top of `_setReferralCode`, and the inline assembly write `assembly { _v := add(_v, number()) }`. `_v` was never read after the assembly write, so the sequence was a zero-value marker leftover with no runtime effect. Full `vault_contract` Foundry suite: 95 of 95 tests pass, confirming no behaviour change. Status is Acknowledged rather than Resolved because we are intentionally deferring the mainnet redeploy for this Informational-severity cleanup: shipping it as a standalone Vault UUPS upgrade would consume admin-key operational overhead and gas for zero security benefit, so the cleaned code is queued for the next scheduled Vault release, which will either be the next CertiK batch that ships a substantive fix or the SEC-2026-0824-001 canonical LiquidationManager / Vault reconciliation, whichever comes first. At that point we will update this reply to Resolved with the new deployed implementation address and upgrade transaction hash.
>
> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by removing redundant code components in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`.

### PRI-19 · Stale Role Entries Remain In `_roles` After Last Member Is Revoked

- **Severity**: Informational · **Final status**: Resolved
- **Location**: `shared/role/RoleStore.sol:116~121`

> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by removing the role from `_roles` when `_roleMembers[role].length() == 0` in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`

### PRI-20 · Concerns Regarding The Vault's On-Chain State

- **Severity**: Informational · **Final status**: Resolved
- **Location**: `rebate_contract/src/contracts/core/referral/RebateDistributor.sol:149~161` · `vault_contract/src/contracts/core/vault/Vault.sol:221~226, 871~874`

> [Primit 2, 08/24/2026]: Status: Acknowledged.
> We confirm that the observed on-chain state on the Vault at `0xdf19d902fcb6295366a06620f76dcb49e686c403` is intentional and matches our design. When the D6 upgrade batch (2026-07-16) migrated the Vault to the PLP-integrated implementation, we called `reinitializeAddPLPAddress` (`reinitializer(5)`) directly to wire the PLP LiquidityVault, which correctly moved `_initialized` from 1 to 5 and, as CertiK notes, made `reinitializeEip712DomainVersion` / `reinitializeSettlementCaps` / `reinitializeProtocolFees` non-callable going forward. For the two settings that are still practically mutable, coverage is preserved via the corresponding admin setters `setDailySettlementCreditCap` and `setDailyUserSettlementCreditCap` for the settlement caps, and `setProtocolFeeRecipient` for the fee recipient — so no operational capability is lost.
>
> The one setting that is now permanently locked is `Vault.VERSION` and its derived `DOMAIN_SEPARATOR`: this is not only acceptable but is exactly the outcome we want. Our EIP-712 domain versions are pinned to `"1.0.0"` for Vault and Rebate and `"1"` for PLP as CertiK correctly quoted from our documentation, because off-chain signatures issued to users are backward-compatibility-critical and any change to VERSION would silently invalidate every outstanding withdraw / close signature. Having the Vault's VERSION locked at the reinitializer level is therefore an effective, defense-in-depth guarantee that the "must not change" contract is enforced by on-chain semantics and not solely by admin discipline.
>
> Regarding the RebateDistributor at `0x726c54c38119d66e8d2b5d7339b57d8b47e48a3b`: yes, `reinitializeEip712DomainVersion` is still callable there because the RD proxy did not consume its `reinitializer` past v2. We confirm the operational commitment that the RD domain version will remain `"1.0.0"` in perpetuity, matching the Vault contract. This commitment is enforced by admin discipline today and will be further hardened once the PRI-01 / PRI-02 governance migration completes, at which point the RD `owner` will be a Gnosis Safe 3-of-5 multisig behind a 48-hour TimelockController; a hypothetical domain-version change would then require Safe quorum and 48-hour on-chain notice, which is enough surface for both the community and CertiK to react. If preferred, we can add a natspec warning on `RebateDistributor.reinitializeEip712DomainVersion` in the next release to make the "keep at 1.0.0" contract explicit in-source, but we do not think a code-level revert on version change is warranted given the Safe+Timelock backstop. No mainnet upgrade is required for this finding.

CertiK's final classification for this finding is **Resolved** on the basis of the above written commitment and on-chain state confirmation; no code change was required in the audit repo.

### PRI-21 · `recordPositionCloseFor()` Requires Self-Authorization Via `permitCloseOperator()`

- **Severity**: Optimization · **Final status**: Acknowledged
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:722~725, 780~783`

> [Primit 2, 08/24/2026]: Status: Acknowledged.
> We agree with the recommendation and applied it verbatim. Code cleanup landed in PR <https://github.com/Primit-io/primit-avax-contracts/pull/23> on the `v2/certik-preliminary-fixes` branch. Both `recordPositionCloseFor` and `_recordPositionCloseAndSettleFor` now skip the `closeOperatorApprovalExpiries` check when `msg.sender == user`, so a position owner submitting their own close does not need to first relay a self-`permitCloseOperator` transaction. Third-party operators still require a live approval, so the delegated-close-operator path is preserved unchanged and no security guarantee is weakened.
>
> TDD coverage in `vault_contract/test/VaultCloseOperatorPermit.t.sol` asserts three behaviours: (a) `recordPositionCloseFor` called by the position owner directly succeeds without any prior permit (test explicitly asserts `closeOperatorApprovalExpiries[user][user] == 0` before the call), (b) `recordPositionCloseAndSettleFor` called by the position owner directly succeeds without any prior permit and correctly debits the user balance and updates the `usedCloseIds` / `usedPositionBalanceSettlements` guards, and (c) a third-party operator without a permit still reverts `CloseOperatorApprovalExpired` (regression guard so the self-submit exemption cannot leak into third-party paths). Full `vault_contract` Foundry suite: 98 of 98 tests pass.
>
> Status is Acknowledged rather than Resolved because we are intentionally deferring the mainnet redeploy for this Optimization-severity fix, matching the deferral we have already communicated for PRI-16 and PRI-18: the mainnet close-and-settle path is not currently exercised end-to-end (see the SEC-2026-0824-001 internal architecture ticket referenced in the PRI-16 reply), so shipping this alone would put the fix into a code path no real user or backend can reach; the change will be picked up by the next canonical Vault release once the backend / contract ABI reconciliation lands. At that point we will update this reply to Resolved with the deployed implementation address and upgrade transaction hash.

### PRI-22 · Confirmation On Incomplete LiquidityVault

- **Severity**: Informational · **Final status**: Acknowledged
- **Location**: `plp_contract/src/LiquidityVault.sol:20~26`

> [Primit 2, 08/24/2026]: Status: Discussion.
> Both design points CertiK raised are intentional; we confirm them below.
>
> (1) `applyFeeShare` and `applyMarketPnl` modify only `totalAssets` and do not move USDC, and `PERFORMANCE_FEE_BP` is declared but not wired into a transfer to BufferPool: this is the v1 design contract already stated in our documentation. PLP v1 is deliberately share-only with `plpShares[user][tier]` equal to the deposited USDC amount at a 1-to-1 ratio, and NAV / real yield accounting are reserved for v1.1. The absence of on-chain USDC transfers in the two `apply*` operator paths is a direct consequence of that: there is no yield source in v1, so there is nothing to transfer. `applyFeeShare` exists to track the notional fee-share credit that will accrue to the buffer in v1.1, and `applyMarketPnl` exists to track the notional market P&L against `totalAssets` for the same reason; both operate against the internal accounting number `totalAssets` rather than the token because the token movement is a v1.1 concern. `PERFORMANCE_FEE_BP` is set to `1000` (10 percent) so the constant is already correct once v1.1 wires the actual profit routing, but under v1 there is no realised profit to route, so no transfer to BufferPool is emitted. This matches the documentation quote CertiK included: "`injectYield` and `absorbLoss` are defined at the protocol design level but not implemented in v1; PLP v1 is share-only (no NAV accounting); `plpShares` equals deposited amount 1-to-1; `totalAssets` and yield accounting are reserved for v1.1."
>
> (2) `LiquidityVault.deposit` and `LiquidityVault.withdraw` call `Vault.debitFromUser` and `Vault.creditToUser` respectively, and these two paths intentionally do NOT invalidate the user's `withdrawNonces`, whereas `settlePositionBalance` / `recordPositionCloseAndSettleFor` / `settleLiquidation` do. The semantic difference is what drives the design: `settlePositionBalance` and `settleLiquidation` are position-PnL settlement operations that can shrink the user's effective spendable balance in ways the backend must re-sign to account for (a previously issued withdraw signature for amount X may now be over the user's remaining balance, and rather than let the user try to spend the stale sig and revert deep inside `withdraw`, we bump `withdrawNonces` so the backend must re-issue). By contrast, `LiquidityVault.deposit` is a same-account balance transfer: the user's vault balance decreases by `amount`, but the amount does not disappear from the user's overall economic position, it moves into `plpShares` under the same user's address. Any previously issued withdraw signature for amount Y still spends validly as long as Y is less than or equal to the user's post-transfer `Vault._balances`; if Y exceeds the remaining balance, `Vault.withdraw` naturally reverts `InsufficientBalance` and the stale signature is effectively self-invalidated on chain without needing to burn a nonce slot. `LiquidityVault.withdraw` is symmetric: `creditToUser` increases the user's Vault balance, and a larger balance cannot cause a pending withdraw signature to consume more than the signature already authorised. Therefore no nonce bump is required on either PLP path, and adding one would only add gas cost without changing the security envelope.
>
> If it would help future auditors, we can add a natspec note on `debitFromUser` and `creditToUser` in the next contract release stating the design contract explicitly ("balance transfer, not a settlement; does not consume `withdrawNonces` because the pending-signature amount is fixed and any over-spend is caught by `InsufficientBalance`"), but no code change is needed to satisfy this finding.

### PRI-23 · `settlePositionBalance()` Unexpectedly Invalidates Pending Withdraw Signatures

- **Severity**: Minor · **Final status**: Acknowledged
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:513`

> [Primit 2, 08/28/2026]: Status: Acknowledged (Discussion).
> Confirming intent and satisfying CertiK's disclosure request.
>
> (1) The nonce-invalidation side effect is intentional: `settlePositionBalance` (and by extension `recordPositionCloseAndSettleFor` via the internal `_settlePositionBalance` path) and `settleLiquidation` all bump `withdrawNonces[user]` because a settlement changes the user's spendable `Vault._balances`. If we did not invalidate, a previously-issued backend-signed withdraw for an amount that was valid pre-settlement could be spent against a post-settlement balance that is now smaller, forcing a revert deep inside `withdraw` rather than a clean re-sign at the backend. Bumping the nonce is the on-chain signal to the off-chain backend that the cached withdraw signature is stale and a new one must be issued against the current balance. This is the same design as `settleLiquidation`, where CertiK acknowledged the intent; PRI-23 correctly points out that `settlePositionBalance` and `recordPositionCloseAndSettleFor` share this behaviour without having said so in the code.
>
> (2) Satisfying the disclosure request: PR <https://github.com/Primit-io/primit-avax-contracts/pull/24> adds dedicated natspec blocks on `settleLiquidation` and `settlePositionBalance` stating the design contract explicitly. The `settleLiquidation` natspec now says "INTENTIONALLY invalidates the user's pending withdraw signatures by incrementing `withdrawNonces[user]`" with the rationale and a note that the invalidated nonce is echoed in the `LiquidationSettled` event for off-chain indexers. The `settlePositionBalance` natspec now says the same thing and explicitly calls out that `recordPositionCloseAndSettleFor` inherits this via `_settlePositionBalance`, with the operational directive "Off-chain backends MUST NOT cache withdraw signatures across settlement events." The invalidated nonce is likewise echoed in the `PositionBalanceSettled` event's `invalidatedNonce` field so any indexer or backend session cache can pick it up in the same block as the settlement.
>
> This is a documentation-only change with no behaviour change; the full `vault_contract` Foundry suite (95 of 95 tests) continues to pass. Deployment: intentionally not broadcast to mainnet as a standalone Discussion-severity docs-fix. The natspec is on the `v2/certik-preliminary-fixes` branch and will be picked up by the next scheduled Vault release (next CertiK batch that ships a substantive fix, or the SEC-2026-0824-001 backend / contract ABI reconciliation, whichever comes first).

### PRI-24 · Confirmation On `params.closeId` In `recordPositionCloseAndSettleFor()`

- **Severity**: Informational · **Final status**: Acknowledged
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:497, 791, 815`

> [Primit 2, 08/24/2026]: Status: Acknowledged (Discussion).
> We confirm the current behaviour is intentional and have made the design contract explicit in-source. Using `params.closeId` as both the audit replay key (`usedCloseIds[closeId]`) and the settlement replay key (`usedPositionBalanceSettlements[closeId]`, accessed via `_settlePositionBalance`) is a deliberate simplification: a single canonical business identifier represents one position close, and locking both guards to the same key means the audit and settlement replay domains cannot drift out of sync.
>
> Two properties depend on this dual-key design and would break if we split them: (a) a completed record-and-settle cannot be split-replayed as either a bare audit re-emit or a bare balance re-settle, because either half of a replay attempt hits an already-consumed guard; (b) the PRI-14 fallback path continues to work cleanly, where a backend has already consumed the settlement side via a direct `settlePositionBalance(user, delta, closeId)` call and an AA operator later submits `recordPositionCloseAndSettleFor` with the same `closeId`, and the flow correctly emits the audit events while skipping the double-charge on the settlement side without the AA caller having to know a second unrelated key. Splitting into two independent keys would give a very small domain-hygiene gain in exchange for a real operational complexity increase: every integrator and every off-chain component would have to carry two independent identifiers for the same close event, keep them in sync at signing time, and re-derive the correct pair when reconciling with the PRI-14 fallback branch. We judged the current single-key design to be the better trade-off.
>
> Fix PR <https://github.com/Primit-io/primit-avax-contracts/pull/25> extends the existing natspec on `recordPositionCloseAndSettleFor` with an explicit "dual-key design contract" block stating the rationale in-source (including the PRI-14 cross-reference), so future auditors and integrators can see the intent without having to reconstruct it from the call graph. This is a documentation-only change with no behaviour change; the full `vault_contract` Foundry suite (95 of 95 tests) continues to pass. Deployment: intentionally not broadcast to mainnet as a standalone Discussion-severity docs-fix. The natspec is on the `v2/certik-preliminary-fixes` branch and will be picked up by the next scheduled Vault release.

### PRI-25 · Confirmation On Access Control For `_settlePositionBalance()` Calls

- **Severity**: Informational · **Final status**: Acknowledged
- **Location**: `vault_contract/src/contracts/core/vault/Vault.sol:478~480, 780~789`

> [Primit 2, 08/24/2026]: Status: Acknowledged (Discussion).
> We confirm the different access-control mechanisms on the two settlement paths are intentional and have made the design contract explicit in-source. The two paths serve two distinct UX / gas-payer patterns while intentionally converging on a single `_settlePositionBalance` internal for balance-mutation accounting:
>
> (1) `settlePositionBalance` is the BACKEND-DIRECT path, gated on `msg.sender == liquidationManager || msg.sender == backendSigner`. This is used when protocol infrastructure drives the transaction: the LiquidationManager after a verified oracle-priced liquidation, or the backend keeper posting a close-event pnl delta. No user permit is required because the caller is a system role, not a user-delegated operator; the backend or LM pays gas.
>
> (2) `recordPositionCloseAndSettleFor` is the AA-OPERATOR path, gated on `closeOperatorApprovalExpiries[user][msg.sender] >= block.timestamp` (with the PRI-21 self-submit shortcut when `msg.sender == user`) plus a backend signature over the full close-settlement payload verified inside `_verifyPositionCloseSettlement`. This is a Permit2-style flow: the user signs once via `permitCloseOperator` to authorize an operator (typically a 4337 bundler or a delegated close-relayer), the operator relays many close-and-settle transactions and pays gas, and the backend co-signature binds `balanceDelta` so the operator cannot pick a different credit/debit.
>
> Two access models exist because two callers with different trust profiles legitimately need to settle balances: the trusted system roles vs a user-delegated operator with a bounded permit window and a per-tx backend counter-signature. Cross-path replay is prevented by the shared `usedPositionBalanceSettlements` mapping keyed by `closeId` (per the PRI-24 dual-key design already documented), so no closeId can be settled twice regardless of which path was used first, and the PRI-14 fallback where a direct-path settle is followed by an AA record-and-settle for the same closeId still emits the audit events cleanly while skipping the double-charge.
>
> Fix PR <https://github.com/Primit-io/primit-avax-contracts/pull/26> adds an explicit "PRI-25 access model" natspec block on both entry points, cross-referencing each other and labelling the paths "BACKEND-DIRECT" and "AA-OPERATOR" respectively, so a future auditor or integrator can see the intent inline without reconstructing it from the modifier chain. This is a documentation-only change with no behaviour change; the full `vault_contract` Foundry suite (95 of 95 tests) continues to pass. Deployment: intentionally not broadcast to mainnet as a standalone Discussion-severity docs-fix. The natspec is on the `v2/certik-preliminary-fixes` branch and will be picked up by the next scheduled Vault release.

### PRI-26 · Confirmation On Fee And Maintenance Margin

- **Severity**: Minor · **Final status**: Resolved
- **Location**: `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol:192~200` · `vault_contract/src/contracts/core/vault/Vault.sol:913~956`

> [Primit 2, 08/24/2026]: Status: Acknowledged.
> We agree with CertiK's observation and have added on-chain defense-in-depth bounds on both sides so the contract no longer relies solely on upstream backend validation for rate / fee sanity. Fix PR <https://github.com/Primit-io/primit-avax-contracts/pull/27> lands the code on the `v2/certik-preliminary-fixes` branch.
>
> LiquidationManager side: three new owner-configurable bounds — `maxLiquidationFeeRate` (default `5e16` = 5%), `minMaintenanceMarginRate` (default `1e15` = 0.1%), `maxMaintenanceMarginRate` (default `5e17` = 50%) — are checked inside `_validateSnapshot` before a backend-signed snapshot is accepted through `updateSnapshot`. Errors `LiquidationFeeRateOutOfBounds` and `MaintenanceMarginRateOutOfBounds` carry the provided value and the active bound so keepers and off-chain monitors can diagnose rejections precisely. Two owner-only setters (`setMaxLiquidationFeeRate` and `setMaintenanceMarginRateBounds`) allow the bounds to be retuned as the fee schedule evolves; both setters reject zero or inverted values so the protection cannot be disabled through the setter.
>
> Vault side: new `maxProtocolFeeAmount` storage (USDC decimals, aggregate cap per settlement) is checked inside `_transferProtocolFees` after `_computeProtocolFeeAmount`. To keep the already-live upgradeable proxy backward-compatible without a reinitializer bump, the field starts at 0 (cap disabled) and the owner explicitly enables it by calling `setMaxProtocolFeeAmount` with a positive value in a follow-up transaction after any future Vault upgrade; the setter rejects zero so once enabled the cap cannot be disabled through the setter. Errors `ProtocolFeeExceedsMax` and `ZeroMaxProtocolFeeAmount` carry the diagnostic data. Storage layout: `__gap` reduced from 31 to 30 slots to account for `maxProtocolFeeAmount`.
>
> TDD coverage: 13 new tests (9 on the LM side, 4 on the Vault side) assert defaults, per-bound reject paths, setter emit + update, and setter rejection of invalid inputs; also assert that a tightened bound retroactively gates subsequent `updateSnapshot` calls, that the existing snap parameters used by every other test are still within the default bounds (regression), and that non-owner callers cannot touch any of the setters. Full `vault_contract` Foundry suite: 108 of 108 tests pass (was 95 of 95).
>
> Deployment: intentionally not broadcast to mainnet as a standalone Discussion-severity fix. Consistent with our deferral for PRI-16 / PRI-18 / PRI-21 / PRI-23 / PRI-24 / PRI-25: the mainnet LiquidationManager path is not functional end-to-end pending the SEC-2026-0824-001 backend / contract ABI reconciliation, and shipping this defense-in-depth alone would put it into code paths no real user or backend can reach today. Both fixes will be picked up by the next canonical release, at which point we will update this reply to Resolved with the deployed implementation address and upgrade transaction hash.
>
> [Primit 2, 08/28/2026]: The team heeded the advice and resolved the issue by adding the corresponding upper and lower bound checks for `maintenanceMarginRate`, an upper bound check for `liquidationFeeRate`, and an upper bound check for `feeAmount` in commit `7c98edf932bbbb37c7af385f31dd892df67da19d`
