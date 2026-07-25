// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @title Price
/// @notice Common price data structure used across Oracle, Liquidation, and Settlement layers.
/// @dev Direct port of gmx-synthetics/contracts/price/Price.sol:10-52 with minor renaming.
library Price {
    /// @notice (min, max) tuple. min = bid-side; max = ask-side. mid = (min+max)/2.
    /// @dev All prices are USD-quoted with 30 decimals (USDC/USDC = 6, USD = 30).
    struct Props {
        uint256 min;
        uint256 max;
    }

    /// @notice Midpoint — for non-directional use cases (e.g., mark price).
    function midPrice(Props memory props) internal pure returns (uint256) {
        return (props.min + props.max) / 2;
    }

    /// @notice Pick the appropriate side based on `maximize` flag.
    ///         maximize=true → return max (worst case for taker / liquidation buyer)
    ///         maximize=false → return min (worst case for maker)
    function pickPrice(Props memory props, bool maximize) internal pure returns (uint256) {
        return maximize ? props.max : props.min;
    }

    /// @notice Sanity check: min <= max, both > 0.
    function isValid(Props memory props) internal pure returns (bool) {
        return props.min > 0 && props.max >= props.min;
    }

    /// @notice Compute relative deviation between two prices in basis points (10000 = 100%).
    /// @dev Used by OracleAggregator to enforce ≤ 2% deviation across 3 sources.
    function relativeDeviationBps(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return type(uint256).max;
        uint256 diff = a > b ? a - b : b - a;
        uint256 base = a > b ? b : a;
        return (diff * 10_000) / base;
    }
}
