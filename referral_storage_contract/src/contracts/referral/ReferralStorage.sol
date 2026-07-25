// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./IReferralStorage.sol";

/**
 * @title ReferralStorage
 * @notice Production-ready referral storage with role-based access control
 * @dev Manages referral codes, referrer tiers, and trader-referrer relationships
 */
contract ReferralStorage is Initializable, IReferralStorage, AccessControlUpgradeable, UUPSUpgradeable {
    // ==================== Roles ====================

    /// @notice Admin role for managing tiers and referrers
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Handler role for vault/rebate contracts to set trader codes
    bytes32 public constant HANDLER_ROLE = keccak256("HANDLER_ROLE");

    // ==================== State Variables ====================

    /// @notice Referral code to owner mapping
    mapping(bytes32 => address) private _codeOwners;

    /// @notice Trader address to referral code mapping
    mapping(address => bytes32) private _traderReferralCodes;

    /// @notice Referrer custom discount shares (overrides tier default)
    mapping(address => uint256) private _referrerDiscountShares;

    /// @notice Referrer tier levels
    mapping(address => uint256) private _referrerTiers;

    /// @notice Tier ID to total rebate mapping (in basis points)
    mapping(uint256 => uint256) private _tierTotalRebates;

    /// @notice Tier ID to discount share mapping (in basis points)
    mapping(uint256 => uint256) private _tierDiscountShares;

    // ==================== Constants ====================

    uint256 public constant BASIS_POINTS = 10_000; // 100%

    /// @dev Internal deployment identifier (v3 - Mainnet 2026-01-27)
    uint256 private constant _INTERNAL_BUILD = 0x52454655;

    // ==================== Events ====================

    event CodeRegistered(bytes32 indexed code, address indexed owner);
    event TraderReferralCodeSet(address indexed trader, bytes32 indexed code, address indexed referrer);
    event TierSet(uint256 indexed tierId, uint256 totalRebate, uint256 discountShare);
    event ReferrerTierSet(address indexed referrer, uint256 indexed tierId);
    event ReferrerDiscountShareSet(address indexed referrer, uint256 discountShare);
    event CodeOwnerChanged(bytes32 indexed code, address indexed oldOwner, address indexed newOwner);

    // ==================== Errors ====================

    error CodeAlreadyExists(bytes32 code);
    error CodeDoesNotExist(bytes32 code);
    error TraderAlreadyHasCode(address trader, bytes32 existingCode);
    error InvalidDiscountShare(uint256 discountShare);
    error InvalidTotalRebate(uint256 totalRebate);
    error ZeroAddress();
    error ZeroCode();

    // ==================== Initialization ====================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ReferralStorage contract
     * @param _admin Admin address for managing tiers and referrers
     */
    function initialize(address _admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        if (_admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ==================== Public Functions ====================

    /**
     * @notice Register a referral code (anyone can register for themselves)
     * @param _code The referral code to register
     */
    function registerCode(bytes32 _code) external override {
        if (_code == bytes32(0)) revert ZeroCode();
        if (_codeOwners[_code] != address(0)) revert CodeAlreadyExists(_code);

        _codeOwners[_code] = msg.sender;
        emit CodeRegistered(_code, msg.sender);
    }

    // ==================== Handler Functions (Vault/Rebate Contracts) ====================

    /**
     * @notice Set trader referral code (called by vault/rebate contracts)
     * @param _account The address of the trader
     * @param _code The referral code to set
     */
    function setTraderReferralCode(address _account, bytes32 _code)
        external
        override
        onlyRole(HANDLER_ROLE)
    {
        if (_account == address(0)) revert ZeroAddress();
        if (_code == bytes32(0)) revert ZeroCode();
        if (_codeOwners[_code] == address(0)) revert CodeDoesNotExist(_code);

        bytes32 existingCode = _traderReferralCodes[_account];
        if (existingCode != bytes32(0)) revert TraderAlreadyHasCode(_account, existingCode);

        // Prevent self-referral
        if (_codeOwners[_code] == _account) revert("Cannot use own code");

        _traderReferralCodes[_account] = _code;
        emit TraderReferralCodeSet(_account, _code, _codeOwners[_code]);
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Set the values for a tier
     * @param _tierId The tier level
     * @param _totalRebate Total rebate rate in basis points (e.g., 1000 = 10%)
     * @param _discountShare Share of total rebate for traders in basis points (e.g., 5000 = 50%)
     */
    function setTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        if (_totalRebate > BASIS_POINTS) revert InvalidTotalRebate(_totalRebate);
        if (_discountShare > BASIS_POINTS) revert InvalidDiscountShare(_discountShare);

        _tierTotalRebates[_tierId] = _totalRebate;
        _tierDiscountShares[_tierId] = _discountShare;

        emit TierSet(_tierId, _totalRebate, _discountShare);
    }

    /**
     * @notice Set the tier for a referrer
     * @param _referrer The address of the referrer
     * @param _tierId The tier level to set
     */
    function setReferrerTier(address _referrer, uint256 _tierId)
        external
        override
        onlyRole(ADMIN_ROLE)
    {
        if (_referrer == address(0)) revert ZeroAddress();

        _referrerTiers[_referrer] = _tierId;
        emit ReferrerTierSet(_referrer, _tierId);
    }

    /**
     * @notice Set custom discount share for a specific referrer (overrides tier default)
     * @param _referrer The address of the referrer
     * @param _discountShare Custom discount share in basis points (0 to disable custom share)
     */
    function setReferrerDiscountShare(address _referrer, uint256 _discountShare)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_referrer == address(0)) revert ZeroAddress();
        if (_discountShare > BASIS_POINTS) revert InvalidDiscountShare(_discountShare);

        _referrerDiscountShares[_referrer] = _discountShare;
        emit ReferrerDiscountShareSet(_referrer, _discountShare);
    }

    /**
     * @notice Grant handler role to a contract (vault/rebate)
     * @param _handler The address of the handler contract
     */
    function grantHandlerRole(address _handler) external onlyRole(ADMIN_ROLE) {
        if (_handler == address(0)) revert ZeroAddress();
        grantRole(HANDLER_ROLE, _handler);
    }

    /**
     * @notice Revoke handler role from a contract
     * @param _handler The address of the handler contract
     */
    function revokeHandlerRole(address _handler) external onlyRole(ADMIN_ROLE) {
        revokeRole(HANDLER_ROLE, _handler);
    }

    // ==================== Governance Functions ====================

    /**
     * @notice Transfer code ownership (governance function)
     * @param _code The referral code
     * @param _newAccount The new owner address
     */
    function govSetCodeOwner(bytes32 _code, address _newAccount)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_newAccount == address(0)) revert ZeroAddress();
        if (_code == bytes32(0)) revert ZeroCode();

        address oldOwner = _codeOwners[_code];
        _codeOwners[_code] = _newAccount;

        emit CodeOwnerChanged(_code, oldOwner, _newAccount);
    }

    // ==================== View Functions ====================

    /**
     * @notice Get the owner of a referral code
     * @param _code The referral code
     * @return The owner address
     */
    function codeOwners(bytes32 _code) external view override returns (address) {
        return _codeOwners[_code];
    }

    /**
     * @notice Get the referral code of a trader
     * @param _account The trader address
     * @return The referral code
     */
    function traderReferralCodes(address _account) external view override returns (bytes32) {
        return _traderReferralCodes[_account];
    }

    /**
     * @notice Get custom discount share for a referrer
     * @param _account The referrer address
     * @return The custom discount share (0 if not set)
     */
    function referrerDiscountShares(address _account) external view override returns (uint256) {
        return _referrerDiscountShares[_account];
    }

    /**
     * @notice Get the tier level of a referrer
     * @param _account The referrer address
     * @return The tier level
     */
    function referrerTiers(address _account) external view override returns (uint256) {
        return _referrerTiers[_account];
    }

    /**
     * @notice Get tier configuration
     * @param _tierLevel The tier level
     * @return totalRebate Total rebate in basis points
     * @return discountShare Trader discount share in basis points
     */
    function tiers(uint256 _tierLevel)
        external
        view
        override
        returns (uint256 totalRebate, uint256 discountShare)
    {
        return (_tierTotalRebates[_tierLevel], _tierDiscountShares[_tierLevel]);
    }

    /**
     * @notice Get trader referral information
     * @param _account The trader address
     * @return code The referral code
     * @return affiliate The referrer address
     */
    function getTraderReferralInfo(address _account)
        external
        view
        override
        returns (bytes32 code, address affiliate)
    {
        code = _traderReferralCodes[_account];
        if (code != bytes32(0)) {
            affiliate = _codeOwners[code];
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    uint256[50] private __gap;
}
