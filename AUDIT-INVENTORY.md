# Primit V2 · Smart Contract Inventory for External Audit

> **Prepared for**:CertiK / PeckShield / SlowMist / other external auditors
> **Date**:2026-07-24
> **Chain**:Avalanche C-Chain mainnet(chainId `43114`)
> **Stablecoin**:USDC only(Circle native · `0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E`)
> **Deployment**:2026-07-24 12:30 UTC · all contracts deployed and Snowscan-verified
> **Contact**:Lee(`lee@zanbarax.com`)· sole engineering owner

---

## 1 · Executive Summary

Primit is a perpetual futures / on-chain custody protocol on Avalanche C-Chain. V2 is a **clean-slate re-deployment** replacing all H1 (2026-01–06) contracts. This document is the single source of truth for the audit scope.

- **8 in-scope contracts** across 6 GitHub repositories(all under [Primit-io](https://github.com/Primit-io))
- **~3,300 SLOC** of hand-written Solidity(excludes OpenZeppelin dependencies)
- **Compiler**:Solidity `0.8.20` · EVM `shanghai` · optimizer runs `200`
- **Test coverage** available on request(forge coverage report per repo)

---

## 2 · Compilation & Tooling Settings

Reproducible builds required for source verification:

| Item | Value |
|---|---|
| Solidity | `0.8.20` |
| EVM version | `shanghai`(all repos) |
| Optimizer | Enabled |
| Optimizer runs | `200` |
| Via IR | `plp_contract` uses `via_ir = true`; others `false` |
| Metadata bytecode hash | `ipfs` |
| CBOR metadata | On |
| Build tool | Foundry(`forge build`) |

**Note on `via_ir` for plp_contract**:enabled to avoid "Stack too deep" in `LiquidityVault.withdraw`. Known Solidity `via_ir` behavior: constant-subexpression-elimination(CSE) may fold `block.timestamp + N` at compile time, so on-chain state assertions in tests use pinned literals.

---

## 3 · Contract Inventory · At a Glance

| # | Contract | Type | Mainnet Address | Snowscan | LOC |
|---|---|---|---|---|---|
| 1 | **Vault** | UUPS Proxy(implementation upgradeable via `Ownable`)| Proxy `0xdf19d902fcb6295366a06620f76dcb49e686c403` | [Proxy](https://snowscan.xyz/address/0xdf19d902fcb6295366a06620f76dcb49e686c403) · [Impl](https://snowscan.xyz/address/0x96a87962fe36db1ec9604a212ee67dab7f9bfa99) | 1074 |
| 2 | **SignatureVerifier** | Library(linked into Vault + Rebate) | (linked · no proxy) | (embedded) | 353 |
| 3 | **LiquidationManager** | Direct contract(`Ownable`) | `0xceb119aadd56b2fe602b634d50c40af21e985de1` | [Snowscan](https://snowscan.xyz/address/0xceb119aadd56b2fe602b634d50c40af21e985de1) | 344 |
| 4 | **ReferralStorage** | UUPS Proxy(`AccessControl`) | Proxy `0x8426de38a4b7b36b04d91826e28d8d3a29394d57` | [Proxy](https://snowscan.xyz/address/0x8426de38a4b7b36b04d91826e28d8d3a29394d57) · [Impl](https://snowscan.xyz/address/0x9a5ef7d0780e2e5a698317e59f02e550da3b4607) | 297 |
| 5 | **RebateDistributor** | UUPS Proxy(`Ownable` + `ReentrancyGuard`) | Proxy `0x726c54c38119d66e8d2b5d7339b57d8b47e48a3b` | [Proxy](https://snowscan.xyz/address/0x726c54c38119d66e8d2b5d7339b57d8b47e48a3b) · [Impl](https://snowscan.xyz/address/0x8d9e273fbe5df22e35534bc2e20aaa2714326d73) | 379 |
| 6 | **LiquidityVault(PLP)** | UUPS Proxy(`AccessControl` + `Pausable`) | Proxy `0xc78786e840b8179b2f3fdbf0fedf69466a51ddf7` | [Proxy](https://snowscan.xyz/address/0xc78786e840b8179b2f3fdbf0fedf69466a51ddf7) · [Impl](https://snowscan.xyz/address/0x7a9702521f1dfe1c078551d0e8e8e54580ebd8d7) | 216 |
| 7 | **BufferPool** | Direct contract(`Ownable`) | `0x83710e300ec5a77c9252be4202f818ee1428d6da` | [Snowscan](https://snowscan.xyz/address/0x83710e300ec5a77c9252be4202f818ee1428d6da) | 38 |
| 8 | **shared/**(RoleStore + Role + Price + Errors) | Libraries / structs | (linked · no proxy) | (embedded) | 233 |

**Total** ~ 2,934 lines + libraries.

Priority for audit(highest to lowest): 1 Vault · 6 LiquidityVault · 3 LiquidationManager · 5 RebateDistributor · 4 ReferralStorage · 7 BufferPool.

---

## 4 · Per-Contract Detail

### 4.1 Vault(Core custody)

**Source** · [`vault_contract/src/contracts/core/vault/Vault.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/vault_contract/src/contracts/core/vault/Vault.sol)  
**Interface** · [`interfaces/IVault.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/vault_contract/src/contracts/interfaces/IVault.sol)

**Function**
- Single custody vault for all user USDC on Primit
- Users deposit ERC20 USDC → internal `_balances[user]` mapping
- Withdrawals require backend-signed EIP-712 message
- Supports settlement paths for position close / liquidation
- Whitelists `plpVaultAddress` for `debitFromUser` / `creditToUser`(PLP integration)

**Inheritance**
`Initializable · ReentrancyGuardUpgradeable · PausableUpgradeable · OwnableUpgradeable · UUPSUpgradeable · IVault`

**Key storage**
- `mapping(address => uint256) private _balances` — canonical solvency floor(per-user internal balance)
- `mapping(address => uint256) public withdrawNonces` — replay guard
- `mapping(address => uint256) public depositedBalances` — cumulative deposit tracking
- `address public plpVaultAddress` — PLP contract whitelist(set once via `reinitializer(5)`)
- `address public backendSigner`
- `bytes32 public DOMAIN_SEPARATOR`
- Additional storage for liquidation settlement caps, protocol fee recipient(all documented in source)

**Key functions**(external / public)
- `deposit(uint256 amount, bytes32 referralCode)` · pull ERC20; increase `_balances[msg.sender]`; independently pausable
- `withdraw(uint256 amount, uint256 deadline, bytes signature)` · EIP-712 signed by backendSigner; decrement `_balances[msg.sender]`; independently pausable
- `getBalance(address user) view` / `getBalances(address[]) view` · read
- `debitFromUser(address user, uint256 amount)` · **only callable by `plpVaultAddress`**
- `creditToUser(address user, uint256 amount)` · **only callable by `plpVaultAddress`**
- Settlement functions for position close and liquidation(gate on backend signer + settlement key uniqueness)

**EIP-712 domain**
- `NAME = "Primit Vault AVAX"`
- `VERSION = "1.0.0"`
- Type hash: `Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)`

**Access control**
- `owner()` = deploy-time address(currently EOA · scheduled to transfer to SAFE multisig prior to public opening — see §7)
- `backendSigner` = mutable via `owner`
- `plpVaultAddress` = immutable after `reinitializer(5)` call

**Upgradability**
- UUPS via `Ownable` gate. Storage layout uses `__gap[31]` to allow future additions without slot collision. Historical reinitializers used: 2(EIP-712 domain version), 3(settlement caps), 4(protocol fees), 5(PLP address).

**Known invariants**(please verify)
- Σ `_balances` ≤ USDC.balanceOf(Vault)(solvency; deposits and settlements must arithmetically preserve this)
- `debitFromUser`/`creditToUser` msg.sender guard is the sole trust boundary between Vault and PLP
- Withdraw signature reused across chains blocked by `verifyingContract` in EIP-712 domain

---

### 4.2 SignatureVerifier(library)

**Source** · [`vault_contract/src/contracts/libraries/SignatureVerifier.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/vault_contract/src/contracts/libraries/SignatureVerifier.sol)  
Also linked into RebateDistributor via [`rebate_contract/src/contracts/libraries/SignatureVerifier.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/rebate_contract/src/contracts/libraries/SignatureVerifier.sol)(identical code).

**Function**
- Wraps `ECDSA.recover` with signature length + zero-address checks
- Computes EIP-712 domain separator from `(name, version, chainId, verifyingContract)`
- Type-hash constants for `Withdraw`, `PositionClose`, `LiquidationSettlement`, `PositionBalanceSettlement`

**Please verify**
- All type-hash strings are canonical(no whitespace differences vs. the on-chain typed data)
- `ECDSA` version is OpenZeppelin `0.8.20`-safe

---

### 4.3 LiquidationManager

**Source** · [`vault_contract/src/contracts/core/liquidation/LiquidationManager.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/vault_contract/src/contracts/core/liquidation/LiquidationManager.sol)

**Function**
- Permissioned keeper entry point for liquidations
- Backend signs a position snapshot(user, size, entry, notional, margin used, etc.)
- Oracle signs the price for the same snapshot
- Both signatures verified on-chain before Vault balance debit

**Inheritance**
`Ownable` · not upgradeable(direct contract — re-deploy on new logic)

**Key storage**
- `IVault public vault`
- `address public backendSigner`
- `address public oracleSigner`
- `address public settlementRecipient`
- `mapping(bytes32 => bool) public usedLiquidationKeys`(dedup)
- `mapping(address => bool) public keeperAllowlist`

**Key functions**
- `liquidate(...)` · double-signature gated; debits Vault
- `setKeeper(address, bool)` · owner-only
- `setSigner(address newOracleSigner)` · owner-only
- `setBackendSigner(address)` · owner-only

**Access control**
- `owner`, `keeperAllowlist[msg.sender]` for triggering; `backendSigner` + `oracleSigner` for signature validation

**Please verify**
- Liquidation key uniqueness(dedup) is enforced before Vault debit
- Signature covers position identity, size, price, and settlement window
- No path to force liquidation without a valid oracle signature
- Cross-chain replay prevented(should include chainId in the signed digest)

---

### 4.4 ReferralStorage

**Source** · [`referral_storage_contract/src/contracts/referral/ReferralStorage.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/referral_storage_contract/src/contracts/referral/ReferralStorage.sol)  
**Interface** · [`IReferralStorage.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/referral_storage_contract/src/contracts/referral/IReferralStorage.sol)

**Function**
- Referral code registry
- Per-referrer tier setting(rebate rate configuration)
- Trader → referrer code binding

**Inheritance**
`AccessControlUpgradeable · UUPSUpgradeable · Initializable`

**Roles**
- `DEFAULT_ADMIN_ROLE` — grant/revoke other roles, upgrade authorization
- `HANDLER_ROLE` — Vault and RebateDistributor contracts(post-deploy grant · currently pending)

**Please verify**
- Code collision impossible(one code → one referrer)
- Tier upper bound is enforced
- Only handlers can set trader code(prevents front-running of referrer selection)

---

### 4.5 RebateDistributor

**Source** · [`rebate_contract/src/contracts/core/referral/RebateDistributor.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/rebate_contract/src/contracts/core/referral/RebateDistributor.sol)

**Function**
- Trader rebate claim: trader claims rebate on paid fees
- Referrer commission claim: referrer claims share of downstream trader fees
- Both actions require backend-signed EIP-712 message

**Inheritance**
`Initializable · OwnableUpgradeable · UUPSUpgradeable · ReentrancyGuardUpgradeable`

**Key storage**
- `IVault public vault`
- `IReferralStorage public referralStorage`
- `IERC20 public usdc`
- `address public backendSigner`
- Per-user nonces for trader and referrer claim paths

**EIP-712 domain**
- `NAME = "Primit Rebate AVAX"`
- `VERSION = "1.0.0"`

**Please verify**
- Trader claim path cannot be replayed for the same trade fees
- Referrer claim path is proportional to actual downstream fees(cannot over-claim)
- Vault is the exclusive USDC source(no residual USDC left in Rebate contract's own balance)

---

### 4.6 LiquidityVault(PLP)

**Source** · [`plp_contract/src/LiquidityVault.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/plp_contract/src/LiquidityVault.sol)

**Function**
- Primit Liquidity Provider: users provide USDC-denominated liquidity to earn a share of market-making + liquidation + trading-fee revenue
- Two lockup tiers: Junior 3-day and Junior 7-day
- Deposits are drawn from user's Vault internal balance(no direct USDC transfer to PLP)
- Withdrawals credit back to Vault internal balance

**Inheritance**
`Initializable · PausableUpgradeable · AccessControlUpgradeable · EIP712Upgradeable · UUPSUpgradeable`

**Roles**
- `DEFAULT_ADMIN_ROLE` — grantRole / revokeRole
- `ADMIN_ROLE` — UUPS `_authorizeUpgrade` gate, pause / unpause
- `OPERATOR_ROLE` — v1.1: `injectYield` / `absorbLoss`(NOT LIVE yet · reserved for v1.1)
- `SIGNER_ROLE` — EIP-712 signature verification

**Key storage**
- `address public usdc` / `address public vault`
- `mapping(address => uint256) public nonces` — replay guard
- `mapping(address => mapping(uint8 => uint256)) public plpShares`
- `mapping(address => mapping(uint8 => uint256)) public lastDepositAt`
- `uint256 public totalAssets`(reserved for v1.1 NAV accounting)

**Key constants(production values)**
- `MIN_DEPOSIT = 100 * 1e6`(100 USDC · 6 decimals)
- `WARMUP_DURATION = 30 minutes`
- `TIER_3D_WEIGHT_BP = 8500` / `TIER_7D_WEIGHT_BP = 10000`
- `PERFORMANCE_FEE_BP = 1000`(10% to BufferPool · v1.1 wire pending)

**Lockup**
- `withdraw` requires `block.timestamp >= lastDepositAt[user][tier] + tier * 1 days`
- Junior 3d(tier=3) → 3-day lockup
- Junior 7d(tier=7) → 7-day lockup

**EIP-712 domain**
- `NAME = "PrimitLiquidityProvider"`
- `VERSION = "1"`
- Type hashes: `PLPDeposit(address user,uint256 amount,uint8 tier,uint256 nonce,uint256 deadline)` / `PLPWithdraw(address user,uint256 shares,uint8 tier,uint256 nonce,uint256 deadline)`

**Please verify**
- `WITHDRAW_TYPEHASH` and `DEPOSIT_TYPEHASH` are cryptographically distinct(prevents deposit-signature-used-as-withdraw attack)
- `Vault.debitFromUser` / `creditToUser` calls balance out arithmetically across deposit + withdraw
- `nonces[user]` is monotonically incremented across BOTH deposit and withdraw(shared counter)
- `_authorizeUpgrade` gate: only `ADMIN_ROLE` can upgrade
- Pausability is independent for deposit and withdraw paths
- `MIN_DEPOSIT` prevents rounding-attack seed(v1.1 NAV accounting)

**Reserved for v1.1(not live)**
- `injectYield(uint256)` and `absorbLoss(uint256)` are defined at protocol design level([Yield Distribution technical design](https://github.com/Primit-io/internal-docs/blob/sprint/plp-v1-2026-0710/2026-07-23-PLP-Yield-Distribution-技术设计.md))but not implemented in v1
- Please audit design assumptions for future compatibility(no storage layout constraint violations expected)

---

### 4.7 BufferPool

**Source** · [`plp_contract/src/BufferPool.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/plp_contract/src/BufferPool.sol)

**Function**
- PLP performance-fee buffer fund
- Receives 10% of every PLP yield injection(v1.1)
- Used to backstop LP losses in tail-event scenarios

**Inheritance**
`Ownable` · not upgradeable

**Key functions**
- `deposit(uint256 amount)` · pull USDC from caller
- `withdraw(uint256 amount, address to)` · **owner-only**(currently EOA · SAFE migration pending)

**Please verify**
- No path to drain by non-owner
- No reentrancy exposure(ERC20 transfer to arbitrary `to` in withdraw)

---

### 4.8 shared/(libraries)

**Sources**
- [`shared/role/RoleStore.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/shared/role/RoleStore.sol)(122 LOC)
- [`shared/role/Role.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/shared/role/Role.sol)(30 LOC)
- [`shared/price/Price.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/shared/price/Price.sol)(40 LOC)
- [`shared/error/Errors.sol`](https://github.com/Primit-io/primit-avax-contracts/blob/v2/mainnet-deploy/shared/error/Errors.sol)(41 LOC)

**Function**
- Adapted from `gmx-synthetics`(direct port with minor renaming)
- Provides Role constants, RoleStore permission set, Price(min, max) struct, and Errors namespace
- Referenced by OracleAggregator(not in current audit scope — see §8)

---

## 5 · Contract Dependency Graph

```
User EOA
   │
   │ (ERC20 approve + transfer)
   ▼
┌──────────────────────────────────────────────────┐
│  USDC (Circle native)                            │
│  0xB97EF9…48a6E                                  │
└──────────────────────────────────────────────────┘
   ▲                                    │
   │ safeTransfer                       │ safeTransferFrom
   │                                    ▼
┌──────────────────────────────────────────────────┐
│  Vault (0xdf19…c403)                             │
│  - _balances[user]                               │
│  - backendSigner ─→ EIP-712 verify               │
└──────────┬────────────────────────────────┬──────┘
           │                                │
           │ debitFromUser                  │ Vault balance mutations
           │ creditToUser                   │ from settlement paths
           ▼                                ▼
┌────────────────────────┐        ┌────────────────────────┐
│  LiquidityVault (PLP)  │        │  LiquidationManager    │
│  0xc78786…dDf7         │        │  0xceb119…5de1         │
│                        │        │  - backend + oracle    │
│  plpShares[user][tier] │        │    double-sig gate     │
└─────────┬──────────────┘        └────────────────────────┘
          │
          │ (v1.1) performance fee
          ▼
┌────────────────────────┐
│  BufferPool            │
│  0x83710e…d6da         │
└────────────────────────┘

┌────────────────────────┐        ┌────────────────────────┐
│  ReferralStorage       │ ◀──────│  RebateDistributor     │
│  0x8426de…4d57         │ query  │  0x726c54…8a3b         │
│  (referrer + tier)     │        │  (rebate claim path)   │
└────────────────────────┘        └────────────────────────┘
```

- Vault is the sole USDC-holding contract
- PLP holds no USDC; only shares accounting
- RebateDistributor pulls from Vault(does not hold USDC)
- ReferralStorage holds no funds; metadata only

---

## 6 · Access-Control Summary

| Contract | Ownership model | Currently held by | Post-deployment target |
|---|---|---|---|
| Vault | `Ownable` | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |
| ReferralStorage | `AccessControl` DEFAULT_ADMIN_ROLE | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |
| RebateDistributor | `Ownable` | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |
| LiquidationManager | `Ownable` | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |
| PLP LiquidityVault | `AccessControl` DEFAULT_ADMIN_ROLE + ADMIN_ROLE | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |
| BufferPool | `Ownable` | EOA `0x2821c28b…F386` | 2-of-3 SAFE multisig |

**Signer / mutable roles**
- `Vault.backendSigner` = `0xBAAf208B9554dBA7C7316EBa3A77669F024Ba047`(EOA · signs withdraw messages)
- `Vault.plpVaultAddress` = `0xc78786…dDf7`(set once via `reinitializer(5)` · immutable)
- `RebateDistributor.backendSigner` = `0xBAAf208B9554dBA7C7316EBa3A77669F024Ba047`
- `LiquidationManager.backendSigner` = `0xBAAf208B9554dBA7C7316EBa3A77669F024Ba047`
- `LiquidationManager.oracleSigner` = `0xBAAf208B9554dBA7C7316EBa3A77669F024Ba047`(v1 shares with backend signer · will be split before public opening)
- `PLP LiquidityVault.SIGNER_ROLE` = `0xBAAf208B9554dBA7C7316EBa3A77669F024Ba047`

---

## 7 · Known Assumptions & Pre-audit Disclosures

The following items are known and either scheduled for remediation or explicitly accepted:

1. **Owner is currently EOA**(V2 clean-slate rationale). Migration to 2-of-3 SAFE multisig will be executed before public opening. Auditors are encouraged to flag any owner-privilege escalations that would be exploitable in the EOA window.

2. **v1 uses a single EOA for both `backendSigner` and `oracleSigner`**(LiquidationManager). Will be split before public opening. If the audit finds any surface where the same key compromises both trust boundaries, please flag.

3. **PLP v1 is share-only(no NAV accounting)**. `plpShares` = deposited amount(1:1). `totalAssets` and yield accounting are reserved for v1.1. Auditors reviewing v1.1 design compatibility should reference [Yield Distribution technical design](https://github.com/Primit-io/internal-docs/blob/sprint/plp-v1-2026-0710/2026-07-23-PLP-Yield-Distribution-技术设计.md)(private repo · access on request).

4. **`ReferralStorage.HANDLER_ROLE` is pending grantRole**. Post-deploy, `Vault` and `RebateDistributor` will be granted `HANDLER_ROLE` so they can set trader-referrer bindings. No user impact until PLP / trading is opened.

5. **`BufferPool` is a direct contract**. Losing the owner key or a critical bug will require a fresh deployment and manual balance migration. Design accepts this for v1(low balance expected). v1.1 may promote to UUPS proxy with timelock.

6. **`via_ir = true` in `plp_contract`**. Known CSE effect: `block.timestamp + N` may be folded. On-chain assertions in tests use pinned literals. Please verify no similar folding hazards in production paths.

7. **Two historically compromised admin keys are hard-locked in deploy scripts**(via `KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c…4Ee1D1b4D8` and `KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2…4BA`). No live V2 contract is owned by these addresses. This is a defense-in-depth measure against accidental re-use.

8. **v1 EIP-712 domain versions are pinned to `"1.0.0"` for Vault and Rebate, and `"1"` for PLP**. Any future upgrade must not change these(off-chain signatures are backward-compatible).

9. **Trading Pair Symbols(`BTCUSDT`, `ETHUSDT`, etc.) are market conventions**, not references to a USDT stablecoin. The stablecoin is USDC only. Please treat pair symbols as opaque market identifiers when reviewing.

10. **No OracleAggregator in v1 scope**. Design exists([`oracle_aggregator/src/`](https://github.com/Primit-io/primit-avax-contracts/tree/v2/mainnet-deploy/oracle_aggregator)) but not deployed for v1. v1 `LiquidationManager` uses off-chain oracle signature only. v1.1 will wire OracleAggregator.

---

## 8 · Out-of-Scope for This Audit

- OracleAggregator(design not yet deployed)
- EarnProduct(not part of V2)
- Backend Rust services and frontend TypeScript
- CI/CD pipeline scripts
- H1 (2026-01–06) contracts — deprecated; user migration handled off-audit
- Test scaffolding under `**/test/` directories

Standard OpenZeppelin dependencies(`4.9.x` compatible via `contracts` and `contracts-upgradeable`)are considered pre-audited and treated as trusted.

---

## 9 · Repository Access

All source is in the [Primit-io](https://github.com/Primit-io) GitHub organization.

**Primary branch for audit**:`v2/mainnet-deploy` under [`primit-avax-contracts`](https://github.com/Primit-io/primit-avax-contracts)

- Contracts: `vault_contract/src/`, `plp_contract/src/`, `rebate_contract/src/`, `referral_storage_contract/src/`, `shared/`
- Deploy scripts: `**/script/Deploy*.s.sol` and `scripts/deploy-v2-avax.sh`
- Tests: `**/test/*.t.sol` — 139 tests(vault: 66, plp: 56, oracle: 17)

Access can be granted to auditor GitHub handles. Please share your GitHub username(s).

**Verification against on-chain bytecode**:each proxy and implementation has been verified on Snowscan(links above). Reproduce with:

```bash
git clone https://github.com/Primit-io/primit-avax-contracts.git
cd primit-avax-contracts
git checkout v2/mainnet-deploy
cd vault_contract && forge build   # (or the relevant subdirectory)
```

---

## 10 · Deployment Metadata

- Deployment `PRIVATE_KEY` deployer:EOA `0x2821c28b7A57c2E0537f5595e8e0eEAEC4b9F386`(nonce 0 before deploy)
- Deployment date:2026-07-24 12:30 UTC
- Total gas spent for full deploy:~0.024 AVAX
- Deployer's transaction trail is on Snowscan under this address

---

## 11 · Contact

**Engineering lead**:Lee(`lee@zanbarax.com`)  
**Response SLA target**:24 hours for clarifying questions during audit

## 12 · Changelog

| Date | Change |
|---|---|
| 2026-07-24 | v1 · Initial audit-ready inventory |
| 2026-08-27 | v2 · Sync 21 CertiK PRI-* preliminary fixes (baseline `d189854` on `primit-avax-contracts`). New `CERTIK-V2-FIXES.md` at repo root indexes each fix (commit / PR / file) plus a current mainnet implementation list with Snowscan-verified links. LT-migration work (PLP `settleUserPnl` · 2026-08-26 · unrelated to CertiK V2 scope) is deliberately EXCLUDED from this sync; note in `CERTIK-V2-FIXES.md §2`. |
