# POST-AUDIT-2026-0917 · Vault.fundVault · Phase 6 On-chain Settlement backing

> **Status** · Post-audit addition · **NOT part of CertiK V2 audit scope** · same track-model as `settleUserPnl` (see CERTIK-V2-FIXES.md scope note).
> **Source PR** (private) · [`primit-avax-contracts#35`](https://github.com/Primit-io/primit-avax-contracts/pull/35) merged 2026-09-16
> **Related** · [`primit-avax-contracts#36`](https://github.com/Primit-io/primit-avax-contracts/pull/36) deploy script + runbook · internal DESIGN-2026-0916-001 (private)

---

## 1 · Why this exists

Phase 6 `PLP.settleUserPnl(user, +profit, sig)` calls `Vault.creditToUser(user, +profit)` internally. `creditToUser` writes storage but transfers no USDC — so a positive settlement wrote an **unbacked IOU**. Attempting `Vault.withdraw` for a user carrying a credited-but-unbacked balance would revert on the ERC20 transfer (Vault USDC balance too low).

`fundVault(uint256)` is the funding entry point that lets Primit ops push USDC into the Vault **as generic backing**, without crediting any user's `_balances`. The invariant we then keep:

```
Σ Vault._balances[users]  ≤  usdc.balanceOf(vault)
```

## 2 · Change (diff shape · full source in `vault_contract/src/contracts/core/vault/Vault.sol`)

Added, no existing behavior modified:

```solidity
event VaultFunded(address indexed funder, uint256 amount, uint256 newTotalFunded);
uint256 public totalFunded;

function fundVault(uint256 amount) external onlyOwner whenNotPaused {
    if (amount == 0) revert ZeroAmount();
    usdc.safeTransferFrom(msg.sender, address(this), amount);
    totalFunded += amount;
    emit VaultFunded(msg.sender, amount, totalFunded);
}
```

Auth · uses existing `onlyOwner` (Vault is already Ownable). No new role, no AccessControl inheritance change. Post-migration to Safe multisig (per PRI-01 / PRI-02 acknowledgement path), fundVault gets multisig-gated automatically.

## 3 · Storage layout diff · slots 0-33 byte-identical to as-audited

```
| slot | pre                    | post                   | note                        |
|------|------------------------|------------------------|-----------------------------|
| 0-32 | (unchanged)            | (unchanged)            |                             |
| 33   | maxProtocolFeeAmount   | maxProtocolFeeAmount   | unchanged                   |
| 34   | __gap (uint256[30])    | totalFunded (uint256)  | NEW at first gap slot       |
| 35   | (was inside __gap[30]) | __gap (uint256[29])    | gap shrunk 30 → 29 slots    |
```

Full JSON diff · `docs/post-audit/2026-0917-vault-fundvault-storage-diff.txt` in this PR. The two non-storage-affecting differences (referralStorage interface AST id, VERSION astId) are compiler-cosmetic (Solc renumbers node ids across builds); they leave the storage slot / offset / type triple identical.

## 4 · Test coverage · 10/10 pure-fn TDD + full suite 128/128 no regression

`vault_contract/test/VaultFundVault.t.sol` · 10 cases:

- `test_totalFunded_starts_at_zero` · post-init default
- `test_fundVault_transfers_usdc_from_caller_to_vault` · ERC20 movement
- `test_fundVault_increments_totalFunded` · monotonic +amount
- `test_fundVault_two_calls_accumulate` · sanity
- `test_fundVault_emits_VaultFunded` · event shape
- `test_fundVault_reverts_when_not_owner` · onlyOwner enforced
- `test_fundVault_reverts_when_paused` · whenNotPaused enforced
- `test_fundVault_reverts_on_zero_amount` · ZeroAmount() error selector
- `test_fundVault_does_not_touch_user_balances` · **critical invariant** · asserts `_balances[userA]`/`_balances[userB]`/`_balances[admin]` and `totalDeposits` unchanged
- `test_fundVault_creates_headroom_for_profit_credit` · integration · deposit → fundVault → invariant holds

Full vault_contract `forge test` after change: **128/128 pass**.

## 5 · Live mainnet deployment · Avalanche C-Chain 43114

| Step | tx / addr | Snowscan |
|---|---|---|
| Deploy new impl(no proxy touch) | tx `0x2799e809b8ac15234e9b031664b0989aace58868139d681f05bada2ef86b8eeb` · impl `0xfcD8fA122acC790c97352c99C6806D2b3Ec605Ab` · deployer `0x2821c28b7A57c2E0537f5595e8e0eEAEC4b9F386` (Vault owner) | [tx](https://snowscan.xyz/tx/0x2799e809b8ac15234e9b031664b0989aace58868139d681f05bada2ef86b8eeb) · [impl](https://snowscan.xyz/address/0xfcd8fa122acc790c97352c99c6806d2b3ec605ab) |
| Upgrade proxy · `upgradeToAndCall(newImpl, "")` | tx `0x9620978dfbbb373ded7595fc0ffcc0b4e73334d5449d11e55975268e07f6c7ac` · block 95,416,351 | [tx](https://snowscan.xyz/tx/0x9620978dfbbb373ded7595fc0ffcc0b4e73334d5449d11e55975268e07f6c7ac) |
| Sanity post-upgrade | `totalFunded() == 0` ✅ · `balances(existingUser)` unchanged ✅ · `implementation() == newImpl` ✅ | on-chain verified |
| Seed 10 USDC · approve + fundVault | approve tx `0x4039613cd3fe8f00b5a796487e080adb92f0d6369017904d6017350b73beaed9` · fundVault tx `0xcbae22bd6203762764c9d59fa5afce556f1a31c1aee35486fe6f121ce0a4a291` | [approve](https://snowscan.xyz/tx/0x4039613cd3fe8f00b5a796487e080adb92f0d6369017904d6017350b73beaed9) · [fund](https://snowscan.xyz/tx/0xcbae22bd6203762764c9d59fa5afce556f1a31c1aee35486fe6f121ce0a4a291) |
| Post-seed state | `totalFunded() = 10.000000 USDC` · Vault USDC pool `21.50 → 31.50` · Σ _balances users ≈ 21.50 · backing headroom ≈ 10 USDC | verified via `cast call` |

## 6 · Live end-to-end verify · 2026-09-16 credit path

Injected synthetic profit fill (rpnl = +2 USDC) into shim off-chain pipeline · off-chain settler credited DB balance · backend submitter signed and submitted `PLP.settleUserPnl(Lee, +2, sig)`:

- Settlement tx · [`0xdc543956...b068666`](https://snowscan.xyz/tx/0xdc543956809cde3b3bb912aca9a44663dbb804402c8c38cc6beb5bc92b068666) · block 95,418,xxx · delta = +2.000000 USDC · fills=1 · nonce=9 · 7s confirmed
- Vault `_balances[Lee]` credited from 5.355988 → 7.281971
- User then called `Vault.withdraw(2 USDC)` from frontend · [tx `0x4305bcd2...ae5cf7`](https://snowscan.xyz/tx/0x4305bcd28c9fc5de1feede9c4edc265f8c1d6e787e8634b1967f870100ae5cf7) · USDC transferred Vault → user wallet · +2 to Lee wallet
- After withdraw · `_balances[Lee] = 5.281971` · Vault USDC pool `31.50 → 29.50` · backing invariant preserved throughout

## 7 · What CertiK reviewers should look at

Requested review scope for this addition (not blocking any live path):

1. **Storage layout invariance** · confirm slots 0-33 unchanged from as-audited baseline · JSON diff attached
2. **Auth surface** · confirm `onlyOwner` is the appropriate gate for a funding entry (vs a dedicated `FUNDER_ROLE`) given Vault's existing Ownable model + planned Safe migration
3. **Invariant preservation** · `Σ _balances[users] ≤ usdc.balanceOf(vault)` — the `fundVault` function itself upholds it; the risk surface is not fundVault but any future function that might credit without pre-funding (there is none today)
4. **Reentrancy** · fundVault has no external callbacks after the USDC pull; `whenNotPaused` and `onlyOwner` gate it. No `nonReentrant` was added — reviewer confirm if wanted
5. **Event shape** · `VaultFunded(funder, amount, newTotalFunded)` matches internal reconciler expectation for computing available backing

## 8 · Follow-ups (tracked separately)

- Optional `defundVault(amount)` reverse-path · deliberately not in v1 (requires invariant guard: `Σ _balances + amount ≤ USDC balance`) · will need its own review round
- `LT_ONCHAIN_SETTLEMENT` modes and PLP.settleUserPnl track (settlement signer, EIP-712 domain, nonce management) · out of scope of this addition, but exercised in §6 verify
- Admin → Safe multisig migration (PRI-01 / PRI-02) · fundVault becomes multisig-gated automatically once done
