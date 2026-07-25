# Primit V2 · Smart Contract Audit Package

> **Public repo for external audit review**
> **Deployed**: 2026-07-24 · Avalanche C-Chain mainnet (chainId 43114)
> **Solidity**: 0.8.20 · Optimizer runs 200 · EVM shanghai
> **Full inventory document**: [AUDIT-INVENTORY.md](./AUDIT-INVENTORY.md)
> **Live addresses**: [deployments/avax-mainnet.json](./deployments/avax-mainnet.json)

---

## What this repo is

A **frozen snapshot of Primit V2 in-scope smart contracts** for external security audit. Contains only what auditors need — no backend / frontend / tests / mocks / build artifacts / deployment scripts / private-key handling material.

Corresponding live mainnet deployment: **2026-07-24**, all contracts Snowscan-verified.

---

## In-scope contracts (8)

| # | Contract | Location | LOC | Type |
|---|---|---|---|---|
| 1 | **Vault** | `vault_contract/src/contracts/core/vault/Vault.sol` | 1074 | UUPS Proxy |
| 2 | **SignatureVerifier** (library) | `vault_contract/src/contracts/libraries/SignatureVerifier.sol` | 353 | Library |
| 3 | **LiquidationManager** | `vault_contract/src/contracts/core/liquidation/LiquidationManager.sol` | 344 | Direct |
| 4 | **ReferralStorage** | `referral_storage_contract/src/contracts/referral/ReferralStorage.sol` | 297 | UUPS Proxy |
| 5 | **RebateDistributor** | `rebate_contract/src/contracts/core/referral/RebateDistributor.sol` | 379 | UUPS Proxy |
| 6 | **LiquidityVault (PLP)** | `plp_contract/src/LiquidityVault.sol` | 216 | UUPS Proxy |
| 7 | **BufferPool** | `plp_contract/src/BufferPool.sol` | 38 | Direct |
| 8 | **shared/** (Role · RoleStore · Price · Errors) | `shared/` | 233 | Libraries |

**Total** ~ 2,934 lines Solidity (excludes OpenZeppelin dependencies).

---

## Repo layout

```
primit-contracts-v2-audit/
├── vault_contract/         (Vault, LiquidationManager, SignatureVerifier, IVault, IReferralStorage)
├── plp_contract/           (LiquidityVault, BufferPool)
├── rebate_contract/        (RebateDistributor + interfaces)
├── referral_storage_contract/  (ReferralStorage + interface)
├── shared/                 (Role, RoleStore, Price, Errors — shared libraries)
├── deployments/
│   └── avax-mainnet.json   (all mainnet addresses + roles + params)
├── install.sh              (one-shot dependency install with pinned versions)
├── AUDIT-INVENTORY.md      (per-contract audit-focused technical detail)
└── README.md               (this file)
```

Each `*_contract/` is an independent Foundry project. Layout preserved from the source monorepo so import paths resolve without modification.

---

## Reproducible build

```bash
# 1. Install pinned dependencies (OpenZeppelin v5.0.2)
./install.sh

# 2. Verify build in each sub-project
cd vault_contract && forge build
cd ../plp_contract && forge build
cd ../rebate_contract && forge build
cd ../referral_storage_contract && forge build
```

Requires:
- Foundry (`forge`, `cast`) — install via `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- Git (for `forge install`)

Pinned dependency versions:
- `foundry-rs/forge-std@v1.9.4`
- `OpenZeppelin/openzeppelin-contracts@v5.0.2`
- `OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2`

Compilation settings (from each `foundry.toml`):

| Item | Value |
|---|---|
| solc | 0.8.20 |
| evm_version | shanghai |
| optimizer | true |
| optimizer_runs | 200 |
| via_ir | `false` (vault / rebate / referral); `true` (plp) |
| bytecode_hash | ipfs |

---

## What's NOT here (deliberately excluded)

| Excluded | Reason |
|---|---|
| Backend Rust code | Non-EVM |
| Frontend TypeScript | Non-EVM |
| `**/test/`, `**/*.t.sol` | Test scaffolding · available on request |
| `**/script/`, `**/*.s.sol` | Deploy scripts · available on request |
| `**/*Mock*.sol` | Mock contracts · not deployed on mainnet |
| `**/broadcast/`, `**/out/`, `**/cache/` | Build artifacts |
| `.env`, `.env.local`, `.env.*` | Secrets |
| `earn_contract/` | Not part of V2 |
| `oracle_aggregator/` | Not deployed in v1 (v1.1 target) |
| `refs/` | Third-party reference material (gmx-v2, orderly) |
| Historical branches (H1 code, D6.3 dev deployments) | Deprecated |

---

## Key security invariants for review

**Vault**
- `Σ _balances[user] ≤ USDC.balanceOf(Vault)` (solvency floor)
- `debitFromUser` / `creditToUser` gated to `plpVaultAddress` only
- Withdraw signatures cannot be cross-chain replayed (EIP-712 `verifyingContract`)
- UUPS `_authorizeUpgrade` guard = `owner`

**LiquidityVault (PLP)**
- Deposit typehash and Withdraw typehash are cryptographically distinct (no cross-fn replay)
- `nonces[user]` monotonic across BOTH deposit and withdraw (shared counter)
- Lockup enforcement: `block.timestamp >= lastDepositAt + tier * 1 days`
- UUPS `_authorizeUpgrade` gated to `ADMIN_ROLE`

**LiquidationManager**
- Requires BOTH `backendSigner` (position) + `oracleSigner` (price) signatures
- Liquidation key uniqueness enforced before Vault debit
- Chain ID present in signed digest (no cross-chain replay)

**RebateDistributor**
- Trader and referrer claim paths have independent nonces
- No excess USDC accumulated in contract (Vault is source)

**BufferPool**
- Only `owner` can withdraw (Ownable)

Full "please verify" checklists per contract in [AUDIT-INVENTORY.md](./AUDIT-INVENTORY.md).

---

## Pre-audit disclosures

10 known assumptions and accepted risks are enumerated in **§7 of [AUDIT-INVENTORY.md](./AUDIT-INVENTORY.md)**. Highlights:

1. **Owner is currently EOA** — clean-slate V2 deployment strategy. Migration to 2-of-3 SAFE multisig scheduled before public opening.
2. **v1 shares `backendSigner` and `oracleSigner`** — will split before public opening.
3. **PLP v1 is share-only** (no NAV / yield accounting) — v1.1 design in a separate document.
4. **`ReferralStorage.HANDLER_ROLE`** — pending grant to Vault and RebateDistributor post-deploy.
5. **`BufferPool` is direct-deployed** — no upgrade path in v1.
6. **`via_ir = true` for `plp_contract`** — CSE folding hazard mitigated in tests via pinned literals.
7. **Two known-compromised admin keys hard-locked** in deploy scripts (`0xF0cB…4Ee1D1b4D8` and `0xa8549df5…4BA`). No V2 contract owned by these.
8. **EIP-712 domain versions pinned**: `"1.0.0"` for Vault/Rebate, `"1"` for PLP. Any future upgrade must not change.
9. **Trading pair symbols** (`BTCUSDT`, `ETHUSDT`, …) are market conventions — the stablecoin is USDC only.
10. **OracleAggregator not in v1 scope** — v1 LiquidationManager uses off-chain oracle signature only.

---

## Contact

**Engineering lead** · Lee (`lee@zanbarax.com`)  
**Response SLA target** · 24 hours for clarifying questions during audit  
**Full source repository (private, for reference on request)** · `github.com/Primit-io/primit-avax-contracts`

---

## License

Source-available for the purposes of external security audit. Full license terms TBD post-audit.

## Change log

| Date | Change |
|---|---|
| 2026-07-25 | v1 · Initial public audit package |
