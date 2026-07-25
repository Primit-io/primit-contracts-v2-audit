// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @title Role
/// @notice Centralized definition of all access-control role constants.
/// @dev Derived from gmx-synthetics/contracts/role/Role.sol with Primit-specific
///      additions for the Snapshot+Oracle+Permissioned-Keeper liquidation model
///      (DR-2026-0506-002 plan B).
library Role {
    /// @dev Top-level admin (Safe multisig + Timelock — see DR-2026-0506-001 §3.3)
    bytes32 internal constant ADMIN = keccak256(abi.encode("ADMIN"));

    /// @dev Liquidation keeper — calls LiquidationManager.executeLiquidation
    bytes32 internal constant LIQUIDATION_KEEPER = keccak256(abi.encode("LIQUIDATION_KEEPER"));

    /// @dev Snapshot keeper — submits PositionSnapshot signed by the backend
    /// @dev Primit-specific (not in GMX V2). Pairs with `ORACLE_SIGNER` below:
    ///      backend signs snapshot off-chain, keeper relays on-chain.
    bytes32 internal constant SNAPSHOT_KEEPER = keccak256(abi.encode("SNAPSHOT_KEEPER"));

    /// @dev Backend oracle signer — its address is checked when verifying snapshot signatures.
    /// @dev Must be rotated independently of ADMIN (see SEC-2026-0428-002 lessons).
    bytes32 internal constant ORACLE_SIGNER = keccak256(abi.encode("ORACLE_SIGNER"));

    /// @dev Price adapter manager — adds / removes oracle price feeds (Chainlink / Pyth / RedStone)
    bytes32 internal constant PRICE_ADAPTER_MANAGER = keccak256(abi.encode("PRICE_ADAPTER_MANAGER"));

    /// @dev Order keeper — placeholder, reserved for future order-flow on-chain extensions
    bytes32 internal constant ORDER_KEEPER = keccak256(abi.encode("ORDER_KEEPER"));
}
