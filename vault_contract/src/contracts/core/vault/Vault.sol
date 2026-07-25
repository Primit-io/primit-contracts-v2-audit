// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IVault.sol";
import "../../libraries/SignatureVerifier.sol";
import "../../referral/IReferralStorage.sol";

/**
 * @title Vault
 * @notice Main vault contract with USDC-only deposits
 * @dev Handles user deposits, withdrawals with backend signature, and referral code management
 */
contract Vault is
    Initializable,
    IVault,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using ECDSA for bytes32;

    // ==================== Constants ====================

    /// @notice EIP-712 Domain name, injected at deployment time
    string public NAME;

    /// @notice Withdraw type hash for EIP-712
    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)");

    // ==================== State Variables ====================

    /// @notice USDC token contract
    IERC20Metadata public usdc;

    /// @notice User settled Vault cash balance from deposits, withdrawals, and closed-position settlements.
    /// @dev This is not account equity and intentionally excludes unrealized PnL from open positions.
    mapping(address => uint256) private _balances;

    /// @notice User cumulative deposited balances: user => amount
    mapping(address => uint256) public override depositedBalances;

    /// @dev Deprecated institutional/market-maker accounting slots.
    ///      Kept private to preserve UUPS storage layout; the accounting mode
    ///      is no longer supported by the Vault ABI.
    mapping(address => uint256) private _deprecatedInstitutionalBalances;
    mapping(address => uint256) private _deprecatedInstitutionalDeposited;
    mapping(address => uint256) private _deprecatedInstitutionalWithdrawn;

    /// @notice Withdrawal nonces for replay protection: user => nonce
    mapping(address => uint256) public override withdrawNonces;

    /// @notice Backend signer address for withdrawal authorization
    address public override backendSigner;

    /// @notice Referral storage contract
    IReferralStorage public referralStorage;

    /// @notice Total deposits (in USDC decimals)
    uint256 public override totalDeposits;

    /// @notice Total withdrawals (in USDC decimals)
    uint256 public override totalWithdrawals;

    /// @notice Minimum deposit amount (in USDC decimals)
    uint256 public override minDeposit;

    /// @notice Minimum withdrawal amount (in USDC decimals)
    uint256 public override minWithdraw;

    /// @notice EIP-712 Domain Separator
    bytes32 public override DOMAIN_SEPARATOR;

    // ==================== Errors ====================

    /// @notice Thrown when amount is below minimum
    error AmountBelowMinimum(uint256 amount, uint256 minimum);

    /// @notice Thrown when signature is expired
    error SignatureExpired(uint256 deadline, uint256 currentTime);

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /// @notice Thrown when balance is insufficient
    error InsufficientBalance(uint256 requested, uint256 available);

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when referral storage is not set
    error ReferralStorageNotSet();

    /// @notice Thrown when domain name is empty
    error EmptyDomainName();

    /// @notice Thrown when domain version is empty
    error EmptyDomainVersion();

    /// @notice Thrown when the caller of a user-gated function does not match
    ///         the `user` parameter (prevents gas-payer / position-owner mismatch).
    error UserMismatch(address caller, address expectedUser);

    /// @notice Thrown when a close operator permission is missing or expired.
    error CloseOperatorApprovalExpired(address user, address operator, uint64 expiresAt, uint256 currentTime);

    /// @notice Thrown when a close id has already been recorded.
    error PositionCloseAlreadyRecorded(bytes32 closeId);

    /// @notice Thrown when a caller of a PLP-gated function is not the authorized PLP LiquidityVault(D-PT-5)
    error OnlyPLP();

    /// @notice Emitted when the PLP LiquidityVault address is set (only once via reinitializer(5))
    event PLPAddressSet(address indexed plp);
    /// @notice Emitted when PLP debits a user's balance
    event BalanceDebitedByPLP(address indexed user, uint256 amount);
    /// @notice Emitted when PLP credits a user's balance
    event BalanceCreditedByPLP(address indexed user, uint256 amount);

    /// @notice Thrown when liquidation settlement caller is not authorized.
    error UnauthorizedLiquidationManager(address caller);

    /// @notice Thrown when a liquidation settlement key has already been used.
    error LiquidationAlreadySettled(bytes32 liquidationKey);

    /// @notice Thrown when a position balance settlement key has already been used.
    error PositionBalanceSettlementAlreadyUsed(bytes32 settlementKey);

    /// @notice Thrown when a signed settlement delta cannot be represented.
    error InvalidSettlementDelta();

    /// @notice Thrown when positive settlement credit would exceed the daily cap.
    error DailySettlementCreditCapExceeded(uint256 requested, uint256 remaining);

    /// @notice Thrown when positive settlement credit would exceed the user's daily cap.
    error DailyUserSettlementCreditCapExceeded(address user, uint256 requested, uint256 remaining);

    /// @notice Thrown when deposits are independently paused.
    error DepositsPaused();

    /// @notice Thrown when withdrawals are independently paused.
    error WithdrawalsPaused();

    /// @notice Thrown when protocol fee recipient has not been configured.
    error ProtocolFeeRecipientNotSet();

    /// @notice Thrown when signed fee fields cannot be represented safely.
    error InvalidFeeAmounts();

    // ==================== Initialization ====================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault
     * @param _usdc USDC token address
     * @param _backendSigner Backend signer address for withdrawal authorization
     * @param _referralStorage Referral storage contract address (can be zero)
     * @param _domainName EIP-712 domain name, should come from backend env
     * @param _domainVersion EIP-712 domain version, should come from backend env
     * @param _owner Owner address with upgrade authority
     */
    function initialize(
        address _usdc,
        address _backendSigner,
        address _referralStorage,
        string memory _domainName,
        string memory _domainVersion,
        address _owner
    ) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        if (_usdc == address(0)) revert ZeroAddress();
        if (_backendSigner == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (bytes(_domainName).length == 0) revert EmptyDomainName();
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        usdc = IERC20Metadata(_usdc);
        backendSigner = _backendSigner;
        NAME = _domainName;
        VERSION = _domainVersion;

        if (_referralStorage != address(0)) {
            referralStorage = IReferralStorage(_referralStorage);
        }

        // Set default minimums (1 token unit in the token's decimals)
        uint8 decimals = usdc.decimals();
        minDeposit = 10 ** decimals;
        minWithdraw = 10 ** decimals;

        // Compute EIP-712 domain separator
        DOMAIN_SEPARATOR = SignatureVerifier.computeDomainSeparator(NAME, VERSION, block.chainid, address(this));
    }

    /**
     * @notice Set EIP-712 domain version during an upgrade migration
     * @param _domainVersion EIP-712 domain version, should come from backend env
     */
    function reinitializeEip712DomainVersion(string memory _domainVersion) external reinitializer(2) onlyOwner {
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        VERSION = _domainVersion;
        DOMAIN_SEPARATOR = SignatureVerifier.computeDomainSeparator(NAME, VERSION, block.chainid, address(this));
    }

    /// @notice Initialize settlement credit caps during an upgrade migration.
    /// @dev Intended for `upgradeToAndCall` so there is no post-upgrade window
    ///      where the zero default blocks all positive settlements.
    function reinitializeSettlementCaps(uint256 globalCap, uint256 perUserCap) external override reinitializer(3) {
        dailySettlementCreditCap = globalCap;
        dailyUserSettlementCreditCap = perUserCap;
        emit DailySettlementCreditCapUpdated(0, globalCap);
        emit DailyUserSettlementCreditCapUpdated(0, perUserCap);
    }

    // ==================== Deposit Functions ====================

    /**
     * @notice Deposit USDC into the vault
     * @dev User must approve this contract to spend USDC first
     * @dev Can set referral code on first deposit
     * @param amount Amount of USDC to deposit (in USDC decimals)
     * @param referralCode Optional referral code (only set on first deposit)
     */
    function deposit(uint256 amount, bytes32 referralCode) external override whenNotPaused nonReentrant {
        if (depositPaused) revert DepositsPaused();

        if (amount < minDeposit) {
            revert AmountBelowMinimum(amount, minDeposit);
        }

        // Transfer USDC from user to contract
        uint256 balanceBefore = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualAmount = usdc.balanceOf(address(this)) - balanceBefore;

        // Update principal and cumulative deposit accounting
        _balances[msg.sender] += actualAmount;
        depositedBalances[msg.sender] += actualAmount;
        totalDeposits += actualAmount;

        // Set referral code if provided and not already set
        if (referralCode != bytes32(0) && address(referralStorage) != address(0)) {
            _setReferralCode(msg.sender, referralCode);
        }

        emit Deposit(msg.sender, actualAmount, referralCode);
    }

    // ==================== Withdrawal Functions ====================

    /**
     * @notice Withdraw USDC from the vault (requires backend signature)
     * @dev Uses EIP-712 signature for authorization
     * @dev Implements nonce-based replay protection
     * @param amount Amount of USDC to withdraw (in USDC decimals)
     * @param deadline Signature expiration timestamp
     * @param signature Backend signature for this withdrawal
     */
    function withdraw(uint256 amount, uint256 deadline, bytes calldata signature)
        external
        override
        whenNotPaused
        nonReentrant
    {
        if (withdrawPaused) revert WithdrawalsPaused();

        // Validate deadline
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        // Validate amount
        if (amount < minWithdraw) {
            revert AmountBelowMinimum(amount, minWithdraw);
        }

        // Get and increment nonce
        uint256 nonce = withdrawNonces[msg.sender];
        withdrawNonces[msg.sender] = nonce + 1;

        // Verify signature
        if (!SignatureVerifier.verifyWithdrawSignature(
                DOMAIN_SEPARATOR, msg.sender, amount, nonce, deadline, signature, backendSigner
            )) {
            revert InvalidSignature();
        }

        // Update balance (Checks-Effects-Interactions pattern).
        // Strict on-chain cap: the backend signer authorizes the amount, but
        // _balances[msg.sender] is the canonical solvency floor. Realized PnL
        // must be settled on-chain through close/liquidation settlement before
        // signing a withdrawal that exceeds the user's chain balance.
        uint256 userBalance = _balances[msg.sender];
        if (amount > userBalance) {
            revert InsufficientBalance(amount, userBalance);
        }
        _balances[msg.sender] = userBalance - amount;
        totalWithdrawals += amount;

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, nonce);
    }

    // ==================== Query Functions ====================

    /**
     * @notice Get user remaining principal balance from deposits
     * @param user User address
     * @return User's remaining principal balance (in USDC decimals)
     */
    function getBalance(address user) external view override returns (uint256) {
        return _balances[user];
    }

    /**
     * @notice Get user cumulative deposited balance
     * @param user User address
     * @return User's cumulative deposited balance (in USDC decimals)
     */
    function getDepositedBalance(address user) external view override returns (uint256) {
        return depositedBalances[user];
    }

    /**
     * @notice Batch get remaining principal balances for multiple users
     * @param users Array of user addresses
     * @return Array of remaining principal balances (in USDC decimals)
     */
    function getBalances(address[] calldata users) external view override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            result[i] = _balances[users[i]];
        }
        return result;
    }

    /**
     * @notice Batch get cumulative deposited balances for multiple users
     * @param users Array of user addresses
     * @return Array of cumulative deposited balances (in USDC decimals)
     */
    function getDepositedBalances(address[] calldata users) external view override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            result[i] = depositedBalances[users[i]];
        }
        return result;
    }

    /**
     * @notice Get user remaining principal balance from deposits
     * @param user User address
     * @return User's remaining principal balance (in USDC decimals)
     */
    function balances(address user) external view override returns (uint256) {
        return _balances[user];
    }

    /**
     * @notice Get current withdrawal nonce for a user
     * @param user User address
     * @return Current nonce
     */
    function getWithdrawNonce(address user) external view override returns (uint256) {
        return withdrawNonces[user];
    }

    /**
     * @notice Get total USDC balance held by contract
     * @return Total USDC balance (in USDC decimals)
     */
    function getTotalBalance() external view override returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @notice Get USDC token decimals
     * @return The number of decimals for USDC token
     */
    function getUsdtDecimals() external view returns (uint8) {
        return usdc.decimals();
    }

    // ==================== Referral Functions ====================

    /**
     * @notice Set referral code (user can call this directly)
     * @param code Referral code to set
     */
    function setReferralCode(bytes32 code) external override {
        _setReferralCode(msg.sender, code);
    }

    /**
     * @notice Configure the contract allowed to settle verified liquidations.
     * @param newManager LiquidationManager contract address.
     */
    function setLiquidationManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert ZeroAddress();
        address oldManager = liquidationManager;
        liquidationManager = newManager;
        emit LiquidationManagerUpdated(oldManager, newManager);
    }

    /**
     * @notice Consume user Vault balance after a verified liquidation.
     * @dev Intentionally not `whenNotPaused`: emergency pause must not block
     *      bad-debt settlement or nonce invalidation for already-risky users.
     */
    function settleLiquidation(
        address user,
        address recipient,
        uint256 requestedAmount,
        bool clearBalance,
        bytes32 liquidationKey
    ) external override nonReentrant returns (uint256 debitedAmount) {
        if (msg.sender != liquidationManager) revert UnauthorizedLiquidationManager(msg.sender);
        if (user == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (liquidationKey == bytes32(0)) revert ZeroAmount();
        if (usedLiquidationSettlements[liquidationKey]) revert LiquidationAlreadySettled(liquidationKey);

        usedLiquidationSettlements[liquidationKey] = true;

        uint256 balance = _balances[user];
        debitedAmount = clearBalance || requestedAmount > balance ? balance : requestedAmount;
        if (debitedAmount != 0) {
            _balances[user] = balance - debitedAmount;
            usdc.safeTransfer(recipient, debitedAmount);
        }

        withdrawNonces[user] += 1;

        emit LiquidationSettled(
            liquidationKey, user, recipient, requestedAmount, debitedAmount, clearBalance, withdrawNonces[user]
        );
    }

    /**
     * @notice Apply a signed position-close balance delta.
     * @dev Positive deltas credit the user's chain balance without moving
     *      tokens. The Vault must already hold enough pooled collateral to back
     *      those credits. Negative deltas debit up to the current chain balance:
     *      if the user's chain balance is 0, a loss settles successfully and
     *      leaves it at 0.
     */
    function settlePositionBalance(address user, int256 balanceDelta, bytes32 settlementKey)
        external
        override
        nonReentrant
        returns (uint256 creditedAmount, uint256 debitedAmount)
    {
        if (msg.sender != liquidationManager && msg.sender != backendSigner) {
            revert UnauthorizedLiquidationManager(msg.sender);
        }

        return _settlePositionBalance(user, balanceDelta, settlementKey);
    }

    function _settlePositionBalance(address user, int256 balanceDelta, bytes32 settlementKey)
        internal
        returns (uint256 creditedAmount, uint256 debitedAmount)
    {
        if (user == address(0)) revert ZeroAddress();
        if (settlementKey == bytes32(0)) revert ZeroAmount();
        if (usedPositionBalanceSettlements[settlementKey]) {
            revert PositionBalanceSettlementAlreadyUsed(settlementKey);
        }
        if (balanceDelta == type(int256).min) revert InvalidSettlementDelta();

        usedPositionBalanceSettlements[settlementKey] = true;

        if (balanceDelta > 0) {
            creditedAmount = uint256(balanceDelta);
            _consumeSettlementCreditCap(user, creditedAmount);
            _balances[user] += creditedAmount;
            totalPositionSettlementCredits += creditedAmount;
        } else if (balanceDelta < 0) {
            uint256 requestedDebit = uint256(-balanceDelta);
            uint256 balance = _balances[user];
            debitedAmount = requestedDebit > balance ? balance : requestedDebit;
            if (debitedAmount != 0) {
                _balances[user] = balance - debitedAmount;
                totalPositionSettlementDebits += debitedAmount;
            }
        }

        withdrawNonces[user] += 1;

        emit PositionBalanceSettled(
            settlementKey, user, balanceDelta, creditedAmount, debitedAmount, _balances[user], withdrawNonces[user]
        );
    }

    /// @notice Configure the maximum positive position settlement credits per day bucket.
    /// @dev A zero cap blocks positive settlement credits. Negative settlement
    ///      debits are not capped by this guard.
    function setDailySettlementCreditCap(uint256 newCap) external override onlyOwner {
        uint256 oldCap = dailySettlementCreditCap;
        dailySettlementCreditCap = newCap;
        emit DailySettlementCreditCapUpdated(oldCap, newCap);
    }

    /// @notice Configure the maximum positive position settlement credits per user per day bucket.
    /// @dev A zero cap blocks positive settlement credits for every user.
    function setDailyUserSettlementCreditCap(uint256 newCap) external override onlyOwner {
        uint256 oldCap = dailyUserSettlementCreditCap;
        dailyUserSettlementCreditCap = newCap;
        emit DailyUserSettlementCreditCapUpdated(oldCap, newCap);
    }

    function _consumeSettlementCreditCap(address user, uint256 amount) internal {
        uint256 cap = dailySettlementCreditCap;
        uint256 userCap = dailyUserSettlementCreditCap;
        uint256 day = block.timestamp / 1 days;

        uint256 used = settlementCreditUsedDay == day ? settlementCreditUsedAmount : 0;
        uint256 remaining = cap > used ? cap - used : 0;
        if (amount > remaining) {
            revert DailySettlementCreditCapExceeded(amount, remaining);
        }

        uint256 userUsed = userSettlementCreditUsedDay[user] == day ? userSettlementCreditUsedAmount[user] : 0;
        uint256 userRemaining = userCap > userUsed ? userCap - userUsed : 0;
        if (amount > userRemaining) {
            revert DailyUserSettlementCreditCapExceeded(user, amount, userRemaining);
        }

        settlementCreditUsedDay = day;
        settlementCreditUsedAmount = used + amount;
        userSettlementCreditUsedDay[user] = day;
        userSettlementCreditUsedAmount[user] = userUsed + amount;
    }

    /// @dev Internal deployment version (v3 - Mainnet 2026-01-27)
    uint256 private constant _VAULT_VERSION = 0x56415556;

    /**
     * @notice Internal function to set referral code
     * @dev Only sets if user doesn't already have a code and code is valid
     * @param user User address
     * @param code Referral code
     */
    function _setReferralCode(address user, bytes32 code) internal {
        uint256 _v = _VAULT_VERSION;
        assembly { _v := add(_v, number()) }
        if (address(referralStorage) == address(0)) {
            return; // Silently return if referral storage not set
        }
        if (code == bytes32(0)) {
            return; // Silently return if code is zero
        }

        // Check if user already has a referral code
        bytes32 existingCode = referralStorage.traderReferralCodes(user);
        if (existingCode != bytes32(0)) {
            return; // User already has a code
        }

        // Check if referral code exists and get owner
        address codeOwner = referralStorage.codeOwners(code);
        if (codeOwner == address(0)) {
            return; // Code doesn't exist
        }
        if (codeOwner == user) {
            return; // User cannot use their own code
        }

        // Set the referral code
        referralStorage.setTraderReferralCode(user, code);

        emit ReferralCodeSet(user, code, codeOwner);
    }

    // ==================== Backend Audit Functions ====================

    /**
     * @notice Record a perpetual position close as an on-chain audit event.
     * @dev The caller is the closing user (who pays gas), but the parameters
     *      must be signed by the backend — this proves the values were
     *      authorised by the off-chain ledger and not forged by the user.
     *      Emits `PositionClosed` and nothing else; no funds, balances, or
     *      nonces are touched. Idempotency is the caller's responsibility:
     *      calling twice with the same `positionId` will emit twice (but
     *      see `deadline` — re-using an old signature past its deadline
     *      reverts).
     * @dev Intentionally NOT `whenNotPaused`: pausing freezes user
     *      deposits/withdrawals but must not block audit-log writes for
     *      closes that already happened in the off-chain ledger.
     * @param positionId Off-chain position UUID, left-padded into bytes32.
     * @param user The user whose position was closed (also expected to be msg.sender,
     *             enforced so the gas-payer matches the position owner).
     * @param symbol Trading pair, e.g. "BTCUSDT".
     * @param realizedPnl Signed realized PnL in collateral-token decimals.
     * @param fee Trading fee charged on this close, in collateral-token decimals.
     * @param closedAt Off-chain close timestamp (unix seconds).
     * @param deadline Signature expiration timestamp (unix seconds).
     * @param signature 65-byte EIP-712 signature from `backendSigner`.
     */
    function recordPositionClose(
        bytes32 positionId,
        address user,
        string calldata symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline,
        bytes calldata signature
    ) external override {
        if (user == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }
        if (msg.sender != user) revert UserMismatch(msg.sender, user);

        if (!SignatureVerifier.verifyPositionCloseSignature(
                DOMAIN_SEPARATOR,
                positionId,
                user,
                symbol,
                realizedPnl,
                fee,
                closedAt,
                deadline,
                signature,
                backendSigner
            )) {
            revert InvalidSignature();
        }

        emit PositionClosed(positionId, user, symbol, realizedPnl, fee, closedAt);
    }

    /**
     * @notice Authorize an operator to submit position-close audit events for a user.
     * @dev Permit2-style UX: user signs once, anyone can relay this permit,
     *      then the operator can submit multiple backend-signed closes until
     *      `expiresAt`. Replay is blocked by `closeOperatorNonces[user]`.
     */
    function permitCloseOperator(
        address user,
        address operator,
        uint64 expiresAt,
        uint256 deadline,
        bytes calldata signature
    ) external override {
        if (user == address(0)) revert ZeroAddress();
        if (operator == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        uint256 nonce = closeOperatorNonces[user];
        if (!SignatureVerifier.verifyCloseOperatorPermitSignature(
                DOMAIN_SEPARATOR, user, operator, expiresAt, nonce, deadline, signature
            )) {
            revert InvalidSignature();
        }

        closeOperatorNonces[user] = nonce + 1;
        closeOperatorApprovalExpiries[user][operator] = expiresAt;

        emit PositionCloseOperatorApproved(user, operator, expiresAt, nonce);
    }

    /**
     * @notice Revoke a previously approved close operator.
     */
    function revokeCloseOperator(address operator) external override {
        if (operator == address(0)) revert ZeroAddress();
        closeOperatorApprovalExpiries[msg.sender][operator] = 0;
        emit PositionCloseOperatorRevoked(msg.sender, operator);
    }

    /**
     * @notice Record a backend-signed close submitted by an approved operator.
     * @dev The backend signature binds `closeId`; otherwise a caller could
     *      replay the same close snapshot with a fresh id and bypass the
     *      `usedCloseIds` guard.
     */
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
    ) external override {
        if (user == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        uint64 expiresAt = closeOperatorApprovalExpiries[user][msg.sender];
        if (expiresAt < block.timestamp) {
            revert CloseOperatorApprovalExpired(user, msg.sender, expiresAt, block.timestamp);
        }

        if (usedCloseIds[closeId]) {
            revert PositionCloseAlreadyRecorded(closeId);
        }

        if (!SignatureVerifier.verifyPositionCloseWithCloseIdSignature(
                DOMAIN_SEPARATOR,
                closeId,
                positionId,
                user,
                symbol,
                realizedPnl,
                fee,
                closedAt,
                deadline,
                signature,
                backendSigner
            )) {
            revert InvalidSignature();
        }

        usedCloseIds[closeId] = true;

        emit PositionClosed(positionId, user, symbol, realizedPnl, fee, closedAt);
        emit PositionCloseRecorded(closeId, positionId, user, msg.sender);
        emit PositionCloseAuditRecorded(closeId, positionId, user, msg.sender, symbol, realizedPnl, fee, closedAt);
    }

    /**
     * @notice Record a backend-signed close audit and settle the user's Vault
     *         balance in the same AA transaction.
     * @dev The backend signature binds the close snapshot and `balanceDelta`,
     *      so an approved AA operator cannot choose a different chain-balance
     *      credit/debit. `closeId` is also used as the settlement key, making
     *      the audit and settlement replay domains identical.
     */
    function recordPositionCloseAndSettleFor(PositionCloseSettlementParams calldata params)
        external
        override
        nonReentrant
        returns (uint256 creditedAmount, uint256 debitedAmount)
    {
        return _recordPositionCloseAndSettleFor(params);
    }

    function _recordPositionCloseAndSettleFor(PositionCloseSettlementParams calldata params)
        internal
        returns (uint256 creditedAmount, uint256 debitedAmount)
    {
        if (params.user == address(0)) revert ZeroAddress();
        if (block.timestamp > params.deadline) {
            revert SignatureExpired(params.deadline, block.timestamp);
        }

        uint64 expiresAt = closeOperatorApprovalExpiries[params.user][msg.sender];
        if (expiresAt < block.timestamp) {
            revert CloseOperatorApprovalExpired(params.user, msg.sender, expiresAt, block.timestamp);
        }

        if (usedCloseIds[params.closeId]) {
            revert PositionCloseAlreadyRecorded(params.closeId);
        }

        _verifyPositionCloseSettlement(params);

        usedCloseIds[params.closeId] = true;

        emit PositionClosed(
            params.positionId, params.user, params.symbol, params.realizedPnl, params.tradingFee, params.closedAt
        );
        emit PositionCloseRecorded(params.closeId, params.positionId, params.user, msg.sender);
        emit PositionCloseAuditRecorded(
            params.closeId,
            params.positionId,
            params.user,
            msg.sender,
            params.symbol,
            params.realizedPnl,
            params.tradingFee,
            params.closedAt
        );

        if (usedPositionBalanceSettlements[params.closeId]) {
            emit PositionBalanceSettled(
                params.closeId, params.user, 0, 0, 0, _balances[params.user], withdrawNonces[params.user]
            );
            return (0, 0);
        }

        (creditedAmount, debitedAmount) = _settlePositionBalance(params.user, params.balanceDelta, params.closeId);
        _transferProtocolFees(params.closeId, params.user, params.tradingFee, params.fundingFee, params.borrowingFee);
        return (creditedAmount, debitedAmount);
    }

    function _verifyPositionCloseSettlement(PositionCloseSettlementParams calldata params) internal view {
        if (!SignatureVerifier.verifyPositionCloseSettlementSignature(DOMAIN_SEPARATOR, params, backendSigner)) {
            revert InvalidSignature();
        }
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Update backend signer address
     * @param newSigner New signer address
     */
    function setBackendSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        address oldSigner = backendSigner;
        backendSigner = newSigner;
        emit BackendSignerUpdated(oldSigner, newSigner);
    }

    /**
     * @notice Set referral storage contract
     * @param _referralStorage Referral storage contract address
     */
    function setReferralStorage(address _referralStorage) external onlyOwner {
        referralStorage = IReferralStorage(_referralStorage);
    }

    /**
     * @notice Pause or unpause deposits independently from withdrawals.
     * @param paused New deposit pause state.
     */
    function setDepositPaused(bool paused) external override onlyOwner {
        depositPaused = paused;
        emit DepositPauseUpdated(paused);
    }

    /**
     * @notice Pause or unpause withdrawals independently from deposits.
     * @param paused New withdrawal pause state.
     */
    function setWithdrawPaused(bool paused) external override onlyOwner {
        withdrawPaused = paused;
        emit WithdrawPauseUpdated(paused);
    }

    /**
     * @notice Initialize protocol fee recipient after upgrading an existing proxy.
     * @param initialRecipient Recipient that receives protocol fees during close settlement.
     */
    /// @notice 一次性升级:授权 PLP LiquidityVault 合约地址(D-PT-5)
    /// @param _plpVault PLP LiquidityVault 合约地址
    function reinitializeAddPLPAddress(address _plpVault) external reinitializer(5) onlyOwner {
        plpVaultAddress = _plpVault;
        emit PLPAddressSet(_plpVault);
    }

    /// @notice PLP 白名单调用:扣减用户余额(deposit 到 PLP 时)
    /// @dev D-PT-5,只允许 plpVaultAddress 调用。用户 _balances 是 solvency floor。
    function debitFromUser(address user, uint256 amount) external {
        if (msg.sender != plpVaultAddress) revert OnlyPLP();
        uint256 userBalance = _balances[user];
        require(userBalance >= amount, "PLP:INSUFFICIENT");
        _balances[user] = userBalance - amount;
        emit BalanceDebitedByPLP(user, amount);
    }

    /// @notice PLP 白名单调用:增加用户余额(withdraw 从 PLP 时)
    /// @dev D-PT-5,只允许 plpVaultAddress 调用
    function creditToUser(address user, uint256 amount) external {
        if (msg.sender != plpVaultAddress) revert OnlyPLP();
        _balances[user] = _balances[user] + amount;
        emit BalanceCreditedByPLP(user, amount);
    }

    function reinitializeProtocolFees(address initialRecipient) external override reinitializer(4) onlyOwner {
        _setProtocolFeeRecipient(initialRecipient);
    }

    /**
     * @notice Update the address that receives protocol fees during close settlement.
     * @param newRecipient New protocol fee recipient.
     */
    function setProtocolFeeRecipient(address newRecipient) external override onlyOwner {
        _setProtocolFeeRecipient(newRecipient);
    }

    function _setProtocolFeeRecipient(address newRecipient) internal {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = protocolFeeRecipient;
        protocolFeeRecipient = newRecipient;
        emit ProtocolFeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function _transferProtocolFees(
        bytes32 closeId,
        address user,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 borrowingFee
    ) internal {
        uint256 feeAmount = _computeProtocolFeeAmount(tradingFee, fundingFee, borrowingFee);
        if (feeAmount == 0) {
            emit ProtocolFeeAccrued(closeId, user, address(usdc), tradingFee, fundingFee, borrowingFee, 0);
            return;
        }

        address token = address(usdc);
        address recipient = protocolFeeRecipient;
        if (recipient == address(0)) revert ProtocolFeeRecipientNotSet();

        usdc.safeTransfer(recipient, feeAmount);
        emit ProtocolFeeAccrued(closeId, user, token, tradingFee, fundingFee, borrowingFee, feeAmount);
    }

    function _computeProtocolFeeAmount(uint256 tradingFee, int256 fundingFee, uint256 borrowingFee)
        internal
        pure
        returns (uint256)
    {
        if (borrowingFee > type(uint256).max - tradingFee) revert InvalidFeeAmounts();
        uint256 positiveFees = tradingFee + borrowingFee;
        uint256 maxInt = uint256(type(int256).max);
        if (positiveFees > maxInt) revert InvalidFeeAmounts();

        if (fundingFee >= 0) {
            uint256 positiveFunding = uint256(fundingFee);
            if (positiveFees > maxInt - positiveFunding) revert InvalidFeeAmounts();
            return positiveFees + positiveFunding;
        }

        if (fundingFee == type(int256).min) revert InvalidFeeAmounts();
        uint256 fundingCredit = uint256(-fundingFee);
        if (fundingCredit >= positiveFees) {
            return 0;
        }
        return positiveFees - fundingCredit;
    }

    /**
     * @notice Pause the contract (emergency only)
     */
    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Emergency withdraw USDC (only when paused)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (!paused()) {
            revert("Not paused");
        }
        if (to == address(0)) revert ZeroAddress();
        usdc.safeTransfer(to, amount);
        emit EmergencyWithdraw(to, amount);
    }

    /**
     * @notice Set minimum deposit amount
     * @param _minDeposit New minimum deposit amount (in USDC decimals)
     */
    function setMinDeposit(uint256 _minDeposit) external onlyOwner {
        minDeposit = _minDeposit;
        emit MinDepositUpdated(_minDeposit);
    }

    /**
     * @notice Set minimum withdrawal amount
     * @param _minWithdraw New minimum withdrawal amount (in USDC decimals)
     */
    function setMinWithdraw(uint256 _minWithdraw) external onlyOwner {
        minWithdraw = _minWithdraw;
        emit MinWithdrawUpdated(_minWithdraw);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    /// @notice EIP-712 Domain version, appended for upgrade-safe storage layout
    string public VERSION;

    /// @notice User => operator => approval expiry timestamp.
    mapping(address => mapping(address => uint64)) public override closeOperatorApprovalExpiries;

    /// @notice User nonce consumed by `permitCloseOperator`.
    mapping(address => uint256) public override closeOperatorNonces;

    /// @notice Unique close ids already recorded by `recordPositionCloseFor`.
    mapping(bytes32 => bool) public override usedCloseIds;

    /// @notice Contract authorized to settle liquidations against Vault balances.
    address public override liquidationManager;

    /// @notice Unique liquidation settlement keys already consumed.
    mapping(bytes32 => bool) public override usedLiquidationSettlements;

    /// @notice Unique position balance settlement keys already consumed.
    mapping(bytes32 => bool) public override usedPositionBalanceSettlements;

    /// @notice Total positive settlement deltas credited to chain balances.
    uint256 public override totalPositionSettlementCredits;

    /// @notice Total negative settlement deltas debited from chain balances.
    uint256 public override totalPositionSettlementDebits;

    /// @notice Maximum positive settlement credits allowed per day bucket.
    uint256 public override dailySettlementCreditCap;

    /// @notice Current day bucket used for settlement credit cap accounting.
    uint256 public override settlementCreditUsedDay;

    /// @notice Positive settlement credits consumed in the current day bucket.
    uint256 public override settlementCreditUsedAmount;

    /// @notice Maximum positive settlement credits allowed per user per day bucket.
    uint256 public override dailyUserSettlementCreditCap;

    /// @notice Per-user day bucket used for settlement credit cap accounting.
    mapping(address => uint256) public override userSettlementCreditUsedDay;

    /// @notice Positive settlement credits consumed by a user in the current user day bucket.
    mapping(address => uint256) public override userSettlementCreditUsedAmount;

    /// @notice Independent deposit pause flag. Global `paused()` still stops deposits first.
    bool public override depositPaused;

    /// @notice Independent withdrawal pause flag. Global `paused()` still stops withdrawals first.
    bool public override withdrawPaused;

    /// @notice Recipient that receives protocol fees during close settlement.
    address public override protocolFeeRecipient;

    /// @dev Legacy storage slot for the removed accrued-fee claim model.
    ///      Do not write to this mapping in new close flows.
    mapping(address => uint256) private __legacyAccruedProtocolFees;

    /// @notice PLP LiquidityVault 授权地址(reinitializer(5) 一次性设置)
    /// @dev    D-PT-5:PLP 通过 debitFromUser / creditToUser 白名单调用扣/加用户余额
    address public plpVaultAddress;

    // gap 从 32 减到 31,因为上面新增了 plpVaultAddress 占 1 slot
    uint256[31] private __gap;
}
