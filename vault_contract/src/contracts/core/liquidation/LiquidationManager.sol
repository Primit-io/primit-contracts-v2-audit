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

    event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OracleSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event SettlementRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event KeeperUpdated(address indexed keeper, bool enabled);
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

        int256 remaining = _remainingCollateral(snap, oraclePrice.price);
        uint256 maintenanceMargin = (snap.sizeUsd * snap.maintenanceMarginRate) / 1e18;
        if (remaining >= int256(maintenanceMargin)) {
            revert NotLiquidatable(remaining, int256(maintenanceMargin));
        }

        uint256 requestedDebit = (snap.sizeUsd * snap.liquidationFeeRate) / 1e18;
        bool clearBalance = remaining < 0;
        liquidationKey = keccak256(abi.encodePacked(positionId, snap.nonce, oraclePrice.price, oraclePrice.updatedAt));

        _snapshots[positionId].status = SnapshotStatus.Liquidated;
        debitedAmount =
            vault.settleLiquidation(snap.user, settlementRecipient, requestedDebit, clearBalance, liquidationKey);

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

    function _validateSnapshot(bytes32 positionId, PositionSnapshot calldata snap) private pure {
        if (
            positionId == bytes32(0) || snap.user == address(0) || snap.symbol == bytes32(0) || snap.sizeUsd == 0
                || snap.sizeTokens == 0 || snap.maintenanceMarginRate == 0 || snap.nonce == 0
                || snap.status != SnapshotStatus.Open
        ) {
            revert InvalidSnapshot(positionId);
        }
    }

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
