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
| PRI-11 | `30c1962` | #14 | `vault_contract/src/contracts/core/vault/Vault.sol` | owner-gated `setPlpVaultAddress` (rotate-friendly setter) |
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
| 1 | **Vault** | `0x0A30176bba21d262cDc652814b8C2A4c9a397b1b` | `0x181f6Bbf7D706cc2B1B14b03Bf86D7B773C2e92D` | [verified](https://snowscan.xyz/address/0x181f6Bbf7D706cc2B1B14b03Bf86D7B773C2e92D#code) | `0xf0a18b6511898c8c4f876acf6e4a9e68fcbcc4ae1fd2a4c65ba5b97ac5a2b697` |
| 2 | **ReferralStorage** | `0x3953a15024c2F391733Bd614F0056f078Cd85199` | `0xF13B031b1A24942d43eE3d3C78A3e3e9667faB7b` | [verified](https://snowscan.xyz/address/0xF13B031b1A24942d43eE3d3C78A3e3e9667faB7b#code) | `0x72d90a8c5c6f4f9d6f273f2ca60241182598f882fd39618940262d9d8544c8b1` |
| 3 | **RebateDistributor** | `0xe2E0cF80E30f3988b2704DED5B0ED3A908083b90` | `0x30b08F944b4b0e8461b439A41bA0eC64DaDe2a9D` | [verified](https://snowscan.xyz/address/0x30b08F944b4b0e8461b439A41bA0eC64DaDe2a9D#code) | `0x7c14288f6a4fb8d4403163087efb1f5d86ad9d81cd9d762920355344a19acac6` |
| 4 | **LiquidationManager** | (direct · non-proxy) | `0x7F74d37C7c5853cFAe133A9Db120591170C4b7F5` | [verified](https://snowscan.xyz/address/0x7F74d37C7c5853cFAe133A9Db120591170C4b7F5#code) | Deploy: `0x045394a7827174f9e49a686f0892dffd5f8a0c8f544ff8e801f2bea69af4c12e` · Vault.setLiquidationManager: `0xd9f3034edb607e96d83d72cb3f2ff95dae49f21ac26c27df48658ad4963bb773` |
| 5 | **LiquidityVault (PLP)** — CertiK-scope impl | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` | *(PRI-03 impl · superseded on 2026-08-26 by an LT-feature upgrade; see note below)* | — | — |
| 5a | **LiquidityVault (PLP)** — current live impl | `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` | `0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe` | [verified](https://snowscan.xyz/address/0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe#code) | `0x7b75c7854882992cb64cae176a063254cb1a77938ef97526569d6ea85689bc85` |
| 6 | **BufferPool** | (direct · non-proxy) | `0x83710e300ec5a77c9252be4202f818ee1428d6da` | [verified](https://snowscan.xyz/address/0x83710e300ec5a77c9252be4202f818ee1428d6da#code) | (unchanged since original deploy) |
| 7 | **shared/** (libraries · RoleStore / Role / Price / Errors) | (linked · no proxy) | (embedded in dependents) | — | — |

### Note on row 5 vs 5a — PLP LiquidityVault

The current live impl `0x88F7AF…10DEe` (row 5a) contains **both** the CertiK PRI-03 fix (`_disableInitializers`) **and** a new `settleUserPnl(user, delta, nonce, deadline, sig)` function that was added on 2026-08-26 for the LiquidityTech backend integration (unrelated to CertiK V2 findings). This audit repo's `plp_contract/src/LiquidityVault.sol` reflects the **PRI-03 baseline only** (no `settleUserPnl`), matching what CertiK's V2 review covers.

If CertiK wants byte-for-byte review of the on-chain impl, the additional surface in `0x88F7AF…10DEe` beyond this repo's source is a single new external function (~30 LOC) plus its typehash + role constant + event + error. Full spec: `DESIGN-2026-0825-002-LT-Settlement-Contract-Signer-Path.md` in the `internal-docs` repo (available on request). This LT-scope surface is scheduled for its own audit pass separately from V2.

---

## 5 · PRI-05 status (as of 2026-09-01)

**Source (this repo):** contains the `unpause()` fix — see Fix Index row above — with three TDD tests. LiquidityVault suite: 55/55 green (including the 3 new PRI-05 tests).

**Mainnet:** upgrade pending. The current live PLP impl is `0x88F7AFbbe3B34Aa33bF78Cd9c2FcAccC08d10DEe` (behind proxy `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7`); it does not yet contain the `unpause()` selector (`0x3f4ba83a`).

**Next steps:**
1. Build a new PLP impl containing this PRI-05 fix plus the existing `settleUserPnl` LT surface (no regression of the LT feature).
2. UUPS `upgradeToAndCall` the PLP proxy; verify new impl bytecode carries the `unpause()` selector.
3. Update this section with the new impl address, Snowscan link, and upgrade tx.
4. Submit revised alleviation to CertiK for **Pending → Resolved** transition.

The PLP proxy address remains stable at `0xc78786e840B8179b2F3fDBf0FEDF69466a51dDf7` across all impl upgrades — user-facing address does not change.

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
