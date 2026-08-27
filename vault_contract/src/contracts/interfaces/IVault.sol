// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface for the vault contract
 * @dev Defines the interface for USDC-based deposit and withdrawal operations
 */
interface IVault {
    struct PositionCloseSettlementParams {
        bytes32 closeId;
        bytes32 positionId;
        address user;
        string symbol;
        int256 realizedPnl;
        uint256 tradingFee;
        int256 fundingFee;
        uint256 borrowingFee;
        int256 balanceDelta;
        uint256 closedAt;
        uint256 deadline;
        bytes signature;
    }

    // ==================== Events ====================

    /// @notice Emitted when a user deposits USDC
    /// @param user The address of the user
    /// @param amount The amount of USDC deposited (in USDC decimals)
    /// @param referralCode The referral code used (if any)
    event Deposit(address indexed user, uint256 amount, bytes32 referralCode);

    /// @notice Emitted when a user withdraws USDC
    /// @param user The address of the user
    /// @param amount The amount of USDC withdrawn (in USDC decimals)
    /// @param nonce The nonce used for this withdrawal
    event Withdraw(address indexed user, uint256 amount, uint256 nonce);

    /// @notice Emitted when a user sets a referral code
    /// @param user The address of the user
    /// @param code The referral code
    /// @param referrer The address of the referrer
    event ReferralCodeSet(address indexed user, bytes32 indexed code, address indexed referrer);

    /// @notice Emitted when the backend signer is updated
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @notice Emitted when the authorized liquidation manager is updated.
    event LiquidationManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when the referral storage contract is updated (CertiK PRI-09).
    event ReferralStorageUpdated(address indexed oldReferralStorage, address indexed newReferralStorage);

    /// @notice Emitted when the EIP-712 domain version is updated (CertiK PRI-09).
    event Eip712DomainVersionUpdated(string oldVersion, string newVersion);

    // Note: Paused and Unpaused events are inherited from OpenZeppelin's Pausable

    /// @notice Emitted during emergency withdrawal
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /// @notice Emitted when minimum deposit amount is updated
    /// @param newMinDeposit The new minimum deposit amount
    event MinDepositUpdated(uint256 newMinDeposit);

    /// @notice Emitted when minimum withdrawal amount is updated
    /// @param newMinWithdraw The new minimum withdrawal amount
    event MinWithdrawUpdated(uint256 newMinWithdraw);

    /// @notice Emitted when deposit pause state is updated.
    event DepositPauseUpdated(bool paused);

    /// @notice Emitted when withdrawal pause state is updated.
    event WithdrawPauseUpdated(bool paused);

    /// @notice Emitted when the protocol fee recipient is updated.
    event ProtocolFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Emitted when a close settlement collects protocol revenue on-chain.
    event ProtocolFeeAccrued(
        bytes32 indexed closeId,
        address indexed user,
        address indexed token,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 borrowingFee,
        uint256 accruedAmount
    );

    /// @notice Emitted when a liquidation consumes user Vault balance.
    /// @param liquidationKey Unique liquidation id, usually keccak256(user, symbol).
    /// @param user The liquidated user.
    /// @param recipient The liquidation payout recipient.
    /// @param requestedAmount Requested debit amount in collateral-token decimals.
    /// @param debitedAmount Actual amount debited and transferred.
    /// @param clearedBalance Whether the settlement intentionally cleared the full user balance.
    /// @param invalidatedNonce User withdraw nonce after invalidating outstanding signatures.
    event LiquidationSettled(
        bytes32 indexed liquidationKey,
        address indexed user,
        address indexed recipient,
        uint256 requestedAmount,
        uint256 debitedAmount,
        bool clearedBalance,
        uint256 invalidatedNonce
    );

    /// @notice Emitted when an authorized settlement manager applies a signed
    ///         balance delta from a position close.
    /// @param settlementKey Unique settlement id to prevent replay.
    /// @param user The settled user.
    /// @param balanceDelta Signed collateral delta; positive credits the user,
    ///        negative debits up to the current chain balance.
    /// @param creditedAmount Amount credited to the user's chain balance.
    /// @param debitedAmount Amount debited from the user's chain balance.
    /// @param newBalance User chain balance after settlement.
    /// @param invalidatedNonce User withdraw nonce after invalidating outstanding signatures.
    event PositionBalanceSettled(
        bytes32 indexed settlementKey,
        address indexed user,
        int256 balanceDelta,
        uint256 creditedAmount,
        uint256 debitedAmount,
        uint256 newBalance,
        uint256 invalidatedNonce
    );

    /// @notice Emitted when the owner changes the daily positive settlement cap.
    event DailySettlementCreditCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Emitted when the owner changes the per-user daily positive settlement cap.
    event DailyUserSettlementCreditCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Emitted when the backend closes a user's perpetual position.
    /// @dev Audit-only log. Does NOT move any funds; balances are settled
    ///      entirely in the off-chain backend. Used for on-chain history
    ///      reconciliation. Callable only by `backendSigner`.
    /// @param positionId Off-chain position UUID, left-padded into bytes32.
    /// @param user The user whose position was closed.
    /// @param symbol Trading pair, e.g. "BTCUSDT".
    /// @param realizedPnl Signed realized PnL in collateral-token decimals
    ///                    (positive = user gained, negative = user lost).
    /// @param fee Trading fee charged on this close, in collateral-token decimals.
    /// @param closedAt Off-chain close timestamp (unix seconds). May lag the
    ///                 block timestamp, so log it explicitly rather than
    ///                 relying on `block.timestamp`.
    event PositionClosed(
        bytes32 indexed positionId,
        address indexed user,
        string symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt
    );

    /// @notice Emitted when `user` authorizes `operator` to submit future
    ///         position-close audit records on the user's behalf.
    event PositionCloseOperatorApproved(
        address indexed user, address indexed operator, uint64 expiresAt, uint256 nonce
    );

    /// @notice Emitted when a user revokes a close operator.
    event PositionCloseOperatorRevoked(address indexed user, address indexed operator);

    /// @notice Emitted with a unique close id for replay-safe reconciliation.
    event PositionCloseRecorded(
        bytes32 indexed closeId, bytes32 indexed positionId, address indexed user, address operator
    );

    /// @notice Emitted with the full backend-signed close snapshot.
    /// @dev Backend listeners should finalize off-chain close state from this
    ///      event after checking all fields against the prepared DB snapshot.
    event PositionCloseAuditRecorded(
        bytes32 indexed closeId,
        bytes32 indexed positionId,
        address indexed user,
        address operator,
        string symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt
    );

    // ==================== Functions ====================

    /// @notice Deposit USDC into the vault
    /// @param amount The amount of USDC to deposit (in USDC decimals)
    /// @param referralCode Optional referral code to set (only on first deposit)
    function deposit(uint256 amount, bytes32 referralCode) external;

    /// @notice Withdraw USDC from the vault (requires backend signature)
    /// @param amount The amount of USDC to withdraw (in USDC decimals)
    /// @param deadline The signature expiration timestamp
    /// @param signature The backend signature for this withdrawal
    function withdraw(uint256 amount, uint256 deadline, bytes calldata signature) external;

    /// @notice CertiK PRI-12 · Withdraw the full _balances[msg.sender] in one call, bypassing
    ///         minWithdraw. Same authorization model as withdraw(): backend signer must co-sign
    ///         the exact balance being drained.
    /// @param deadline The signature expiration timestamp
    /// @param signature The backend signature covering (msg.sender, currentBalance, currentNonce, deadline)
    function withdrawAll(uint256 deadline, bytes calldata signature) external;

    /// @notice Get the user's remaining principal balance from deposits
    /// @param user The address of the user
    /// @return The remaining principal balance (in USDC decimals)
    function getBalance(address user) external view returns (uint256);

    /// @notice Get the user's cumulative deposited amount
    /// @param user The address of the user
    /// @return The cumulative deposited amount (in USDC decimals)
    function getDepositedBalance(address user) external view returns (uint256);

    /// @notice Batch get remaining principal balances for multiple users
    /// @param users Array of user addresses
    /// @return Array of remaining principal balances (in USDC decimals)
    function getBalances(address[] calldata users) external view returns (uint256[] memory);

    /// @notice Batch get cumulative deposited balances for multiple users
    /// @param users Array of user addresses
    /// @return Array of cumulative deposited balances (in USDC decimals)
    function getDepositedBalances(address[] calldata users) external view returns (uint256[] memory);

    /// @notice Get the current withdrawal nonce for a user
    /// @param user The address of the user
    /// @return The current nonce
    function getWithdrawNonce(address user) external view returns (uint256);

    /// @notice Get the total USDC balance held by the contract
    /// @return The total USDC balance (in USDC decimals)
    function getTotalBalance() external view returns (uint256);

    /// @notice Set a referral code (user can set this directly)
    /// @param code The referral code to set
    function setReferralCode(bytes32 code) external;

    /// @notice Consume user Vault balance after a verified liquidation.
    /// @param user The liquidated user.
    /// @param recipient Recipient of the debited collateral.
    /// @param requestedAmount Amount requested in collateral-token decimals. May
    ///        be zero when the settlement only records liquidation idempotency
    ///        and invalidates outstanding withdrawal signatures.
    /// @param clearBalance If true, consume the user's entire remaining Vault balance.
    /// @param liquidationKey Unique settlement key to prevent replay.
    /// @return debitedAmount Actual amount debited and transferred.
    function settleLiquidation(
        address user,
        address recipient,
        uint256 requestedAmount,
        bool clearBalance,
        bytes32 liquidationKey
    ) external returns (uint256 debitedAmount);

    /// @notice Apply a signed position-close balance delta.
    /// @dev Positive deltas credit user chain balance. Negative deltas debit up
    ///      to the current chain balance, so a user with 0 chain balance remains
    ///      at 0 after a loss.
    /// @param user Settled user.
    /// @param balanceDelta Signed collateral delta.
    /// @param settlementKey Unique settlement key to prevent replay.
    /// @return creditedAmount Amount credited to user balance.
    /// @return debitedAmount Amount debited from user balance.
    function settlePositionBalance(address user, int256 balanceDelta, bytes32 settlementKey)
        external
        returns (uint256 creditedAmount, uint256 debitedAmount);

    /// @notice Configure the maximum positive position settlement credits per UTC-like day bucket.
    function setDailySettlementCreditCap(uint256 newCap) external;

    /// @notice Configure the maximum positive position settlement credits per user per UTC-like day bucket.
    function setDailyUserSettlementCreditCap(uint256 newCap) external;

    /// @notice Upgrade initializer for settlement credit caps.
    function reinitializeSettlementCaps(uint256 globalCap, uint256 perUserCap) external;

    /// @notice Upgrade initializer for protocol fee recipient.
    function reinitializeProtocolFees(address initialRecipient) external;

    /// @notice Record a perpetual position close as an on-chain audit event.
    /// @dev Caller is the closing user (`msg.sender == user`, gas-payer matches
    ///      position owner). Parameters must be signed by `backendSigner` via
    ///      EIP-712. Emits `PositionClosed` and does nothing else — no funds,
    ///      balances, or nonces are touched. Idempotency is the caller's
    ///      responsibility: re-submitting with the same `positionId` emits a
    ///      duplicate event (but a past `deadline` will revert).
    /// @param positionId Off-chain position UUID, left-padded into bytes32.
    /// @param user The user whose position was closed (must equal msg.sender).
    /// @param symbol Trading pair, e.g. "BTCUSDT".
    /// @param realizedPnl Signed realized PnL in collateral-token decimals.
    /// @param fee Trading fee charged on this close, in collateral-token decimals.
    /// @param closedAt Off-chain close timestamp (unix seconds).
    /// @param deadline Signature expiration timestamp (unix seconds).
    /// @param signature 65-byte EIP-712 signature from `backendSigner`.
    function recordPositionClose(
        bytes32 positionId,
        address user,
        string calldata symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Authorize an operator to submit multiple future close records.
    /// @param user User granting the permission.
    /// @param operator Operator/relayer that may call `recordPositionCloseFor`.
    /// @param expiresAt Permission expiry timestamp.
    /// @param deadline Permit signature expiry timestamp.
    /// @param signature EIP-712 signature from `user`.
    function permitCloseOperator(
        address user,
        address operator,
        uint64 expiresAt,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Revoke an operator previously granted by `permitCloseOperator`.
    function revokeCloseOperator(address operator) external;

    /// @notice Record a close on behalf of `user`, submitted by an approved operator.
    function recordPositionCloseFor(
        bytes32 closeId,
        bytes32 positionId,
        address user,
        string calldata symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Record a close audit and settle the user's Vault balance in one approved-operator call.
    function recordPositionCloseAndSettleFor(PositionCloseSettlementParams calldata params)
        external
        returns (uint256 creditedAmount, uint256 debitedAmount);

    // ==================== State Variables ====================

    // Note: usdc is IERC20 type, accessible via address(usdc)

    /// @notice User remaining principal balances from deposits
    function balances(address user) external view returns (uint256);

    /// @notice User cumulative deposited balances
    function depositedBalances(address user) external view returns (uint256);

    /// @notice Withdrawal nonces for replay protection
    function withdrawNonces(address user) external view returns (uint256);

    /// @notice Close-operator permit nonces for replay protection.
    function closeOperatorNonces(address user) external view returns (uint256);

    /// @notice Expiry timestamp for a user/operator close approval.
    function closeOperatorApprovalExpiries(address user, address operator) external view returns (uint64);

    /// @notice Whether a unique close id has already been recorded.
    function usedCloseIds(bytes32 closeId) external view returns (bool);

    /// @notice Contract authorized to settle liquidations against Vault balances.
    function liquidationManager() external view returns (address);

    /// @notice Whether a liquidation settlement key has already been consumed.
    function usedLiquidationSettlements(bytes32 liquidationKey) external view returns (bool);

    /// @notice Whether a position balance settlement key has already been consumed.
    function usedPositionBalanceSettlements(bytes32 settlementKey) external view returns (bool);

    /// @notice Total positive settlement deltas credited to chain balances.
    function totalPositionSettlementCredits() external view returns (uint256);

    /// @notice Total negative settlement deltas debited from chain balances.
    function totalPositionSettlementDebits() external view returns (uint256);

    /// @notice Maximum positive settlement credits allowed per day bucket. Zero blocks positive credits.
    function dailySettlementCreditCap() external view returns (uint256);

    /// @notice Current day bucket used for settlement credit cap accounting.
    function settlementCreditUsedDay() external view returns (uint256);

    /// @notice Positive settlement credits consumed in the current day bucket.
    function settlementCreditUsedAmount() external view returns (uint256);

    /// @notice Maximum positive settlement credits allowed per user per day bucket.
    function dailyUserSettlementCreditCap() external view returns (uint256);

    /// @notice Per-user day bucket used for settlement credit cap accounting.
    function userSettlementCreditUsedDay(address user) external view returns (uint256);

    /// @notice Positive settlement credits consumed by a user in the current user day bucket.
    function userSettlementCreditUsedAmount(address user) external view returns (uint256);

    /// @notice Backend signer address
    function backendSigner() external view returns (address);

    /// @notice Whether deposits are paused independently from the global emergency pause.
    function depositPaused() external view returns (bool);

    /// @notice Whether withdrawals are paused independently from the global emergency pause.
    function withdrawPaused() external view returns (bool);

    /// @notice Pause or unpause deposits independently from withdrawals.
    function setDepositPaused(bool paused) external;

    /// @notice Pause or unpause withdrawals independently from deposits.
    function setWithdrawPaused(bool paused) external;

    /// @notice Protocol fee recipient.
    function protocolFeeRecipient() external view returns (address);

    /// @notice Update protocol fee recipient.
    function setProtocolFeeRecipient(address newRecipient) external;

    /// @notice Minimum deposit amount
    function minDeposit() external view returns (uint256);

    /// @notice Minimum withdrawal amount
    function minWithdraw() external view returns (uint256);

    /// @notice Total deposits
    function totalDeposits() external view returns (uint256);

    /// @notice Total withdrawals
    function totalWithdrawals() external view returns (uint256);

    /// @notice EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
