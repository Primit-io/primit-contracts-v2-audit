// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface for the vault contract
 * @dev Defines the interface for USDC-based deposit and withdrawal operations
 */
interface IVault {
    // ==================== Events ====================

    /// @notice Emitted when a user deposits USDC
    /// @param user The address of the user
    /// @param amount The amount of USDC deposited (in USDC decimals)
    /// @param referralCode The referral code used (if any)
    event Deposit(
        address indexed user,
        uint256 amount,
        bytes32 referralCode
    );

    /// @notice Emitted when a user withdraws USDC
    /// @param user The address of the user
    /// @param amount The amount of USDC withdrawn (in USDC decimals)
    /// @param nonce The nonce used for this withdrawal
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when a user sets a referral code
    /// @param user The address of the user
    /// @param code The referral code
    /// @param referrer The address of the referrer
    event ReferralCodeSet(
        address indexed user,
        bytes32 indexed code,
        address indexed referrer
    );

    /// @notice Emitted when the backend signer is updated
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event BackendSignerUpdated(
        address indexed oldSigner,
        address indexed newSigner
    );

    // Note: Paused and Unpaused events are inherited from OpenZeppelin's Pausable

    /// @notice Emitted during emergency withdrawal
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event EmergencyWithdraw(
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when minimum deposit amount is updated
    /// @param newMinDeposit The new minimum deposit amount
    event MinDepositUpdated(uint256 newMinDeposit);

    /// @notice Emitted when minimum withdrawal amount is updated
    /// @param newMinWithdraw The new minimum withdrawal amount
    event MinWithdrawUpdated(uint256 newMinWithdraw);

    // ==================== Functions ====================

    /// @notice Deposit USDC into the vault
    /// @param amount The amount of USDC to deposit (in USDC decimals)
    /// @param referralCode Optional referral code to set (only on first deposit)
    function deposit(
        uint256 amount,
        bytes32 referralCode
    ) external;

    /// @notice Withdraw USDC from the vault (requires backend signature)
    /// @param amount The amount of USDC to withdraw (in USDC decimals)
    /// @param deadline The signature expiration timestamp
    /// @param signature The backend signature for this withdrawal
    function withdraw(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Get the USDC balance of a user
    /// @param user The address of the user
    /// @return The USDC balance (in USDC decimals)
    function getBalance(address user) external view returns (uint256);

    /// @notice Batch get USDC balances for multiple users
    /// @param users Array of user addresses
    /// @return Array of balances (in USDC decimals)
    function getBalances(
        address[] calldata users
    ) external view returns (uint256[] memory);

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

    // ==================== State Variables ====================

    // Note: usdc is IERC20 type, accessible via address(usdc)

    /// @notice User USDC balances
    function balances(address user) external view returns (uint256);

    /// @notice Withdrawal nonces for replay protection
    function withdrawNonces(address user) external view returns (uint256);

    /// @notice Backend signer address
    function backendSigner() external view returns (address);

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

