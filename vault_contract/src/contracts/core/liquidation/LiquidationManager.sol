// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../../interfaces/IVault.sol";

/**
 * @title LiquidationManager
 * @notice Permissioned keeper liquidation entrypoint backed by backend-signed
 *         position snapshots and independently signed oracle prices.
 * @dev This is the minimal on-chain enforcement layer for the Snapshot +
 *      Oracle design: Vault custody remains unchanged, but liquidation no
 *      longer finalizes from backend DB state alone. The manager recomputes
 *      margin requirements on-chain before debiting Vault balances.
 */
contract LiquidationManager is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    enum PositionSide {
        Long,
        Short
    }

    enum SnapshotStatus {
        None,
        Open,
        Liquidated,
        Closed
    }

    /// @notice Backend-signed position snapshot fed into `updateSnapshot` / `liquidate`.
    /// @dev    CertiK PRI-15 · Precision contract for all numeric fields.
    ///         USD-denominated fields: `sizeUsd`, `collateral`, `accumulatedFunding`,
    ///         `accumulatedBorrowing`, and (as computed inside `_remainingCollateral`) `positionValue`
    ///         are ALL denominated in **1e18-scaled USD** (i.e. "wad" precision). This holds even
    ///         though the underlying settlement token (USDC on Avalanche) has 6 decimals — the
    ///         backend up-scales USD-side quantities to 1e18 before signing, and the on-chain
    ///         `_remainingCollateral` math preserves that scale. `sizeTokens` is in the token's
    ///         native wei-scale (1e18 for typical ETH-scaled synth exposures). Rate fields
    ///         `maintenanceMarginRate` and `liquidationFeeRate` are unitless 1e18 fixed-point
    ///         fractions (e.g. `5e16` = 5%, `5e15` = 0.5%). The formula
    ///         `positionValue = (sizeTokens * markPrice) / 1e18` therefore lands `positionValue`
    ///         back in 1e18-USD, matching `sizeUsd` for the pnl subtraction. Downstream Vault-side
    ///         debit accounting is decoupled from this scale — callers of `Vault.settleLiquidation`
    ///         are responsible for down-scaling the settlement obligation to the Vault's
    ///         `_balances` decimals (USDC decimals on mainnet) before requesting a debit.
    /// @param  user Position owner.
    /// @param  symbol Trading pair as `keccak256("BTCUSDT")`-style bytes32 identifier.
    /// @param  side Long / Short.
    /// @param  sizeUsd Notional exposure in **1e18-USD wad** (backend-computed).
    /// @param  sizeTokens Underlying token amount in **1e18-wei** (backend-computed).
    /// @param  collateral Collateral in **1e18-USD wad** (backend-computed effective collateral).
    /// @param  accumulatedFunding Signed cumulative funding fee in **1e18-USD wad**.
    /// @param  accumulatedBorrowing Signed cumulative borrowing fee in **1e18-USD wad**.
    /// @param  maintenanceMarginRate Unitless 1e18 fixed-point fraction (`5e16` = 5%).
    /// @param  liquidationFeeRate  Unitless 1e18 fixed-point fraction (`5e15` = 0.5%).
    /// @param  nonce Backend-monotonic replay guard per (user, symbol).
    /// @param  updatedAt Backend snapshot timestamp (unix seconds).
    /// @param  status See `SnapshotStatus`.
    struct PositionSnapshot {
        address user;
        bytes32 symbol;
        PositionSide side;
        uint256 sizeUsd;
        uint256 sizeTokens;
        uint256 collateral;
        int256 accumulatedFunding;
        int256 accumulatedBorrowing;
        uint256 maintenanceMarginRate;
        uint256 liquidationFeeRate;
        uint64 nonce;
        uint64 updatedAt;
        SnapshotStatus status;
    }

    /// @notice Independently-signed oracle price payload consumed by `liquidate`.
    /// @dev    CertiK PRI-15 · `price` is denominated in **1e18-scaled USD per whole token**
    ///         (i.e. `markPrice = usdPerToken * 1e18`). Combined with `sizeTokens` in 1e18-wei,
    ///         the `_remainingCollateral` formula `(sizeTokens * markPrice) / 1e18` yields a
    ///         `positionValue` in 1e18-USD wad that matches the `sizeUsd` / `collateral` scale.
    struct OraclePrice {
        bytes32 symbol;
        uint256 price;
        uint64 updatedAt;
        uint64 maxStaleness;
        bytes signature;
    }

    IVault public immutable vault;

    address public backendSigner;
    address public oracleSigner;
    address public settlementRecipient;

    mapping(address => bool) public keepers;
    mapping(bytes32 => PositionSnapshot) private _snapshots;

    /// @notice CertiK PRI-16 · Maximum age (seconds) of a signed PositionSnapshot at liquidation time.
    /// @dev    Enforced in liquidate() alongside the existing oracle staleness check to prevent
    ///         a keeper from combining a fresh mark price with a multi-hour stale snapshot
    ///         (whose accumulatedFunding / accumulatedBorrowing / collateral no longer reflect
    ///         the current position state). Owner-configurable via setMaxSnapshotAge; default 300s
    ///         (5 minutes) leaves a reasonable window for keepers to submit while blocking the
    ///         indefinite-age vector CertiK flagged.
    uint256 public maxSnapshotAge;

    /// @notice CertiK PRI-26 · Upper bound (1e18 wad) on snap.liquidationFeeRate accepted by updateSnapshot.
    /// @dev    Default 5e16 = 5%. Owner-configurable via setMaxLiquidationFeeRate. Rejects 0 in setter
    ///         so protection cannot be disabled.
    uint256 public maxLiquidationFeeRate;

    /// @notice CertiK PRI-26 · Lower bound (1e18 wad) on snap.maintenanceMarginRate accepted by updateSnapshot.
    /// @dev    Default 1e15 = 0.1%. Owner-configurable via setMaintenanceMarginRateBounds.
    uint256 public minMaintenanceMarginRate;

    /// @notice CertiK PRI-26 · Upper bound (1e18 wad) on snap.maintenanceMarginRate accepted by updateSnapshot.
    /// @dev    Default 5e17 = 50%. Owner-configurable via setMaintenanceMarginRateBounds.
    uint256 public maxMaintenanceMarginRate;

    bytes32 public constant SNAPSHOT_HASH_DOMAIN = keccak256("PRIMIT_LIQUIDATION_SNAPSHOT_V1");
    bytes32 public constant ORACLE_HASH_DOMAIN = keccak256("PRIMIT_LIQUIDATION_ORACLE_V1");

    error ZeroAddress();
    error InvalidSignature();
    error UnauthorizedKeeper(address caller);
    error SnapshotNotOpen(bytes32 positionId);
    error StaleNonce(uint64 incoming, uint64 current);
    error InvalidSnapshot(bytes32 positionId);
    error SymbolMismatch(bytes32 snapshotSymbol, bytes32 oracleSymbol);
    error StaleOraclePrice(uint64 updatedAt, uint64 maxStaleness, uint256 currentTime);
    error NotLiquidatable(int256 remainingCollateral, int256 maintenanceMargin);
    /// @notice CertiK PRI-16 · thrown when the backend-signed PositionSnapshot is older than maxSnapshotAge.
    error StaleSnapshot(uint64 updatedAt, uint256 maxAge, uint256 currentTime);
    /// @notice CertiK PRI-16 · setMaxSnapshotAge must not disable staleness protection.
    error ZeroMaxSnapshotAge();
    /// @notice CertiK PRI-26 · snap.liquidationFeeRate exceeds the on-chain upper bound.
    error LiquidationFeeRateOutOfBounds(uint256 provided, uint256 max);
    /// @notice CertiK PRI-26 · snap.maintenanceMarginRate is outside the on-chain bounds.
    error MaintenanceMarginRateOutOfBounds(uint256 provided, uint256 min, uint256 max);
    /// @notice CertiK PRI-26 · setter must not disable a bound (zero max would disable).
    error InvalidRateBounds();

    event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OracleSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event SettlementRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event KeeperUpdated(address indexed keeper, bool enabled);
    /// @notice CertiK PRI-16 · Emitted when the owner updates maxSnapshotAge.
    event MaxSnapshotAgeUpdated(uint256 oldAge, uint256 newAge);
    /// @notice CertiK PRI-26 · Emitted when the owner updates the max liquidation fee rate bound.
    event MaxLiquidationFeeRateUpdated(uint256 oldMax, uint256 newMax);
    /// @notice CertiK PRI-26 · Emitted when the owner updates the maintenance margin rate bounds.
    event MaintenanceMarginRateBoundsUpdated(uint256 oldMin, uint256 oldMax, uint256 newMin, uint256 newMax);
    event SnapshotUpdated(
        bytes32 indexed positionId, address indexed user, bytes32 indexed symbol, uint64 nonce, uint64 updatedAt
    );
    event SnapshotClosed(bytes32 indexed positionId, uint64 nonce);
    event LiquidationExecuted(
        bytes32 indexed positionId,
        bytes32 indexed liquidationKey,
        address indexed user,
        bytes32 symbol,
        uint256 markPrice,
        int256 remainingCollateral,
        uint256 maintenanceMargin,
        uint256 debitedAmount,
        address keeper
    );

    /// @notice CertiK PRI-07 · Emitted when a liquidation's position-scoped
    ///         obligation (fee + shortfall) exceeds the user's Vault balance.
    /// @param  obligation   fee + shortfall computed on-chain
    /// @param  debitedAmount actual amount debited from Vault (capped by balance)
    /// @param  badDebt      obligation - debitedAmount (uncovered residue)
    event LiquidationBadDebt(
        bytes32 indexed positionId,
        bytes32 indexed liquidationKey,
        address indexed user,
        uint256 obligation,
        uint256 debitedAmount,
        uint256 badDebt
    );

    constructor(
        address _vault,
        address _backendSigner,
        address _oracleSigner,
        address _settlementRecipient,
        address _owner
    ) Ownable(_owner) {
        if (
            _vault == address(0) || _backendSigner == address(0) || _oracleSigner == address(0)
                || _settlementRecipient == address(0) || _owner == address(0)
        ) {
            revert ZeroAddress();
        }
        vault = IVault(_vault);
        backendSigner = _backendSigner;
        oracleSigner = _oracleSigner;
        settlementRecipient = _settlementRecipient;
        // CertiK PRI-16 · default 5 minutes; owner can retune via setMaxSnapshotAge.
        maxSnapshotAge = 300;
        // CertiK PRI-26 · conservative defaults (1e18 wad). All owner-tunable.
        maxLiquidationFeeRate = 5e16;      // 5%
        minMaintenanceMarginRate = 1e15;   // 0.1%
        maxMaintenanceMarginRate = 5e17;   // 50%
    }

    function setBackendSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address oldSigner = backendSigner;
        backendSigner = newSigner;
        emit BackendSignerUpdated(oldSigner, newSigner);
    }

    function setOracleSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address oldSigner = oracleSigner;
        oracleSigner = newSigner;
        emit OracleSignerUpdated(oldSigner, newSigner);
    }

    function setSettlementRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = settlementRecipient;
        settlementRecipient = newRecipient;
        emit SettlementRecipientUpdated(oldRecipient, newRecipient);
    }

    function setKeeper(address keeper, bool enabled) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        keepers[keeper] = enabled;
        emit KeeperUpdated(keeper, enabled);
    }

    /// @notice CertiK PRI-16 · owner-configurable max snapshot age (seconds).
    /// @dev    Zero is rejected to prevent disabling the staleness protection; use a small
    ///         positive value (e.g. 30-60s) for tighter guarantees or a larger one for keeper slack.
    function setMaxSnapshotAge(uint256 newAge) external onlyOwner {
        if (newAge == 0) revert ZeroMaxSnapshotAge();
        emit MaxSnapshotAgeUpdated(maxSnapshotAge, newAge);
        maxSnapshotAge = newAge;
    }

    /// @notice CertiK PRI-26 · owner-configurable upper bound on snap.liquidationFeeRate.
    /// @dev    Rejects 0 so the protection cannot be disabled. Value is 1e18 wad (5e16 = 5%).
    function setMaxLiquidationFeeRate(uint256 newMax) external onlyOwner {
        if (newMax == 0) revert InvalidRateBounds();
        emit MaxLiquidationFeeRateUpdated(maxLiquidationFeeRate, newMax);
        maxLiquidationFeeRate = newMax;
    }

    /// @notice CertiK PRI-26 · owner-configurable lower/upper bounds on snap.maintenanceMarginRate.
    /// @dev    Rejects newMin == 0 (would let 0-margin snaps through) and newMax == 0 or newMin > newMax.
    ///         Values are 1e18 wad (1e15 = 0.1% min, 5e17 = 50% max).
    function setMaintenanceMarginRateBounds(uint256 newMin, uint256 newMax) external onlyOwner {
        if (newMin == 0 || newMax == 0 || newMin > newMax) revert InvalidRateBounds();
        emit MaintenanceMarginRateBoundsUpdated(
            minMaintenanceMarginRate, maxMaintenanceMarginRate, newMin, newMax
        );
        minMaintenanceMarginRate = newMin;
        maxMaintenanceMarginRate = newMax;
    }

    function updateSnapshot(bytes32 positionId, PositionSnapshot calldata snap, bytes calldata backendSignature)
        external
    {
        _validateSnapshot(positionId, snap);
        if (_recoverSnapshotSigner(positionId, snap, backendSignature) != backendSigner) {
            revert InvalidSignature();
        }

        PositionSnapshot storage current = _snapshots[positionId];
        if (current.status == SnapshotStatus.Liquidated || current.status == SnapshotStatus.Closed) {
            revert SnapshotNotOpen(positionId);
        }
        if (snap.nonce <= current.nonce) revert StaleNonce(snap.nonce, current.nonce);

        _snapshots[positionId] = snap;
        emit SnapshotUpdated(positionId, snap.user, snap.symbol, snap.nonce, snap.updatedAt);
    }

    function closeSnapshot(bytes32 positionId, uint64 nonce, bytes calldata backendSignature) external {
        PositionSnapshot storage current = _snapshots[positionId];
        if (current.status != SnapshotStatus.Open) revert SnapshotNotOpen(positionId);
        if (nonce <= current.nonce) revert StaleNonce(nonce, current.nonce);

        bytes32 digest = _closeHash(positionId, nonce).toEthSignedMessageHash();
        if (digest.recover(backendSignature) != backendSigner) revert InvalidSignature();

        current.status = SnapshotStatus.Closed;
        current.nonce = nonce;
        emit SnapshotClosed(positionId, nonce);
    }

    function liquidate(bytes32 positionId, OraclePrice calldata oraclePrice)
        external
        returns (bytes32 liquidationKey, uint256 debitedAmount)
    {
        if (!keepers[msg.sender]) revert UnauthorizedKeeper(msg.sender);

        PositionSnapshot memory snap = _snapshots[positionId];
        if (snap.status != SnapshotStatus.Open) revert SnapshotNotOpen(positionId);
        if (snap.symbol != oraclePrice.symbol) revert SymbolMismatch(snap.symbol, oraclePrice.symbol);
        if (_recoverOracleSigner(oraclePrice) != oracleSigner) revert InvalidSignature();
        if (block.timestamp > uint256(oraclePrice.updatedAt) + uint256(oraclePrice.maxStaleness)) {
            revert StaleOraclePrice(oraclePrice.updatedAt, oraclePrice.maxStaleness, block.timestamp);
        }
        // CertiK PRI-16 · reject a snapshot whose accumulated funding/borrowing/collateral values
        // are older than maxSnapshotAge; without this, a keeper could combine an hours-old snapshot
        // with a freshly-signed mark price and produce a distorted _remainingCollateral verdict.
        if (block.timestamp > uint256(snap.updatedAt) + maxSnapshotAge) {
            revert StaleSnapshot(snap.updatedAt, maxSnapshotAge, block.timestamp);
        }

        int256 remaining = _remainingCollateral(snap, oraclePrice.price);
        uint256 maintenanceMargin = (snap.sizeUsd * snap.maintenanceMarginRate) / 1e18;
        if (remaining >= int256(maintenanceMargin)) {
            revert NotLiquidatable(remaining, int256(maintenanceMargin));
        }

        // CertiK PRI-07 · Position-scoped liquidation obligation.
        // Pre-fix: `clearBalance = remaining < 0` caused Vault.settleLiquidation to
        // debit the user's ENTIRE shared _balances (unassigned deposits, PLP credits
        // and every other position's collateral) whenever a single position had a
        // deficit. Now we cap the debit to (fee + shortfall) for THIS position and
        // record any uncovered residue as bad debt.
        uint256 liquidationFee = (snap.sizeUsd * snap.liquidationFeeRate) / 1e18;
        uint256 shortfall = remaining < 0 ? uint256(-remaining) : 0;
        uint256 obligation = liquidationFee + shortfall;
        liquidationKey = keccak256(abi.encodePacked(positionId, snap.nonce, oraclePrice.price, oraclePrice.updatedAt));

        _snapshots[positionId].status = SnapshotStatus.Liquidated;
        // Always pass clearBalance=false. Vault caps to min(obligation, balance);
        // the leftover balance is preserved for the user's other positions.
        debitedAmount =
            vault.settleLiquidation(snap.user, settlementRecipient, obligation, false, liquidationKey);

        uint256 badDebt = obligation > debitedAmount ? obligation - debitedAmount : 0;
        if (badDebt != 0) {
            emit LiquidationBadDebt(positionId, liquidationKey, snap.user, obligation, debitedAmount, badDebt);
        }

        emit LiquidationExecuted(
            positionId,
            liquidationKey,
            snap.user,
            snap.symbol,
            oraclePrice.price,
            remaining,
            maintenanceMargin,
            debitedAmount,
            msg.sender
        );
    }

    function snapshotHash(bytes32 positionId, PositionSnapshot calldata snap) external view returns (bytes32) {
        return _snapshotHash(positionId, snap);
    }

    function oracleHash(OraclePrice calldata oraclePrice) external view returns (bytes32) {
        return _oracleHash(oraclePrice.symbol, oraclePrice.price, oraclePrice.updatedAt, oraclePrice.maxStaleness);
    }

    function closeHash(bytes32 positionId, uint64 nonce) external view returns (bytes32) {
        return _closeHash(positionId, nonce);
    }

    function remainingCollateral(bytes32 positionId, uint256 markPrice) external view returns (int256) {
        PositionSnapshot memory snap = _snapshots[positionId];
        if (snap.status != SnapshotStatus.Open) revert SnapshotNotOpen(positionId);
        return _remainingCollateral(snap, markPrice);
    }

    function snapshotStatus(bytes32 positionId) external view returns (SnapshotStatus) {
        return _snapshots[positionId].status;
    }

    function snapshotNonce(bytes32 positionId) external view returns (uint64) {
        return _snapshots[positionId].nonce;
    }

    function _validateSnapshot(bytes32 positionId, PositionSnapshot calldata snap) private view {
        if (
            positionId == bytes32(0) || snap.user == address(0) || snap.symbol == bytes32(0) || snap.sizeUsd == 0
                || snap.sizeTokens == 0 || snap.maintenanceMarginRate == 0 || snap.nonce == 0
                || snap.status != SnapshotStatus.Open
        ) {
            revert InvalidSnapshot(positionId);
        }
        // CertiK PRI-26 · numerical bounds on backend-signed rate fields (defense in depth).
        if (snap.liquidationFeeRate > maxLiquidationFeeRate) {
            revert LiquidationFeeRateOutOfBounds(snap.liquidationFeeRate, maxLiquidationFeeRate);
        }
        if (
            snap.maintenanceMarginRate < minMaintenanceMarginRate
                || snap.maintenanceMarginRate > maxMaintenanceMarginRate
        ) {
            revert MaintenanceMarginRateOutOfBounds(
                snap.maintenanceMarginRate, minMaintenanceMarginRate, maxMaintenanceMarginRate
            );
        }
    }

    /// @notice Compute remaining collateral (unrealized margin) for a position at a given mark price.
    /// @dev    CertiK PRI-15 · Precision contract for callers and readers:
    ///           - `snap.sizeTokens` and `markPrice` are BOTH in **1e18 scale**
    ///             (`sizeTokens` = token wei-count; `markPrice` = usdPerToken * 1e18).
    ///             The multiplication is 1e36; dividing by 1e18 lands `positionValue` in **1e18-USD wad**.
    ///           - `snap.sizeUsd` is in **1e18-USD wad** (backend-signed), so the pnl subtraction is same-scale.
    ///           - `snap.collateral`, `snap.accumulatedFunding`, `snap.accumulatedBorrowing` are all in
    ///             **1e18-USD wad**, matching the pnl.
    ///           - Return value is in **1e18-USD wad** (signed).
    ///         Callers that later pass a settlement obligation to `Vault.settleLiquidation` are responsible
    ///         for down-scaling from 1e18-USD to the Vault's `_balances` decimals (USDC decimals on mainnet).
    ///         See the natspec on `PositionSnapshot` above for per-field details.
    function _remainingCollateral(PositionSnapshot memory snap, uint256 markPrice) private pure returns (int256) {
        uint256 positionValue = (snap.sizeTokens * markPrice) / 1e18;
        int256 pnl = snap.side == PositionSide.Long
            ? int256(positionValue) - int256(snap.sizeUsd)
            : int256(snap.sizeUsd) - int256(positionValue);

        return int256(snap.collateral) + pnl - snap.accumulatedFunding - snap.accumulatedBorrowing;
    }

    function _recoverSnapshotSigner(bytes32 positionId, PositionSnapshot calldata snap, bytes calldata signature)
        private
        view
        returns (address)
    {
        return _snapshotHash(positionId, snap).toEthSignedMessageHash().recover(signature);
    }

    function _recoverOracleSigner(OraclePrice calldata oraclePrice) private view returns (address) {
        return _oracleHash(oraclePrice.symbol, oraclePrice.price, oraclePrice.updatedAt, oraclePrice.maxStaleness)
            .toEthSignedMessageHash().recover(oraclePrice.signature);
    }

    function _snapshotHash(bytes32 positionId, PositionSnapshot calldata snap) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                SNAPSHOT_HASH_DOMAIN,
                block.chainid,
                address(this),
                positionId,
                _snapshotIdentityHash(snap.user, snap.symbol, snap.side, snap.nonce, snap.updatedAt, snap.status),
                _snapshotMarginHash(
                    snap.sizeUsd,
                    snap.sizeTokens,
                    snap.collateral,
                    snap.accumulatedFunding,
                    snap.accumulatedBorrowing,
                    snap.maintenanceMarginRate,
                    snap.liquidationFeeRate
                )
            )
        );
    }

    function _snapshotIdentityHash(
        address user,
        bytes32 symbol,
        PositionSide side,
        uint64 nonce,
        uint64 updatedAt,
        SnapshotStatus status
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(user, symbol, side, nonce, updatedAt, status));
    }

    function _snapshotMarginHash(
        uint256 sizeUsd,
        uint256 sizeTokens,
        uint256 collateral,
        int256 accumulatedFunding,
        int256 accumulatedBorrowing,
        uint256 maintenanceMarginRate,
        uint256 liquidationFeeRate
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                sizeUsd,
                sizeTokens,
                collateral,
                accumulatedFunding,
                accumulatedBorrowing,
                maintenanceMarginRate,
                liquidationFeeRate
            )
        );
    }

    function _oracleHash(bytes32 symbol, uint256 price, uint64 updatedAt, uint64 maxStaleness)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(ORACLE_HASH_DOMAIN, block.chainid, address(this), symbol, price, updatedAt, maxStaleness)
        );
    }

    function _closeHash(bytes32 positionId, uint64 nonce) private view returns (bytes32) {
        return keccak256(abi.encode(SNAPSHOT_HASH_DOMAIN, block.chainid, address(this), positionId, nonce, "CLOSE"));
    }
}
