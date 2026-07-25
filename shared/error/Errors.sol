// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @title Errors
/// @notice Centralized custom errors for all Primit AVAX contracts.
/// @dev Using a single library reduces bytecode and unifies error catalog
///      for off-chain decoding (subgraph, monitoring, alerting).
library Errors {
    // -----------------------------------------------------------------------
    // Access / permission
    // -----------------------------------------------------------------------
    error Unauthorized(address account, bytes32 role);
    error ZeroAddress();

    // -----------------------------------------------------------------------
    // Oracle
    // -----------------------------------------------------------------------
    error StalePrice(bytes32 symbol, uint256 publishedAt, uint256 maxAge);
    error InsufficientPriceSources(bytes32 symbol, uint256 got, uint256 required);
    error PriceDeviationTooLarge(bytes32 symbol, uint256 deviationBps, uint256 maxBps);
    error InvalidPrice(bytes32 symbol, int256 raw);
    error AdapterNotRegistered(bytes32 symbol, address adapter);

    // -----------------------------------------------------------------------
    // Liquidation
    // -----------------------------------------------------------------------
    error PositionNotLiquidatable(bytes32 positionKey, uint256 mmr, uint256 mmrThreshold);
    error InvalidSnapshot(bytes32 positionKey, bytes32 reason);
    error SnapshotExpired(uint256 signedAt, uint256 currentTime, uint256 maxAge);
    error NonceAlreadyUsed(bytes32 positionKey, uint256 nonce);
    error NonceMonotonicityBroken(bytes32 positionKey, uint256 lastNonce, uint256 incoming);
    error PayoutCapExceeded(uint256 payoutUsd, uint256 capUsd);
    error InvalidSignature(address recovered, address expected);

    // -----------------------------------------------------------------------
    // Generic
    // -----------------------------------------------------------------------
    error NotImplemented();
    error AlreadyInitialized();
    error Paused();
}
