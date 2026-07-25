// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/IReferralRebate.sol";
import "../../interfaces/IVault.sol";
import "../../libraries/SignatureVerifier.sol";
import "../../referral/IReferralStorage.sol";

/**
 * @title RebateDistributor
 * @notice Contract for handling referral rebate distribution in USDC
 * @dev Manages rebate claiming with backend signature and batch distribution
 */
contract RebateDistributor is
    Initializable,
    IReferralRebate,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ==================== State Variables ====================

    /// @dev Basis points divisor: 1e4 = 100%
    uint256 private constant BASIS_POINTS = 10_000;

    /// @dev Internal deployment marker (v3 - Mainnet 2026-01-27)
    uint256 private constant _REBATE_BUILD = 0x52454243;

    /// @notice Backend signer address for rebate claim authorization
    address public override backendSigner;

    /// @notice Vault contract address
    IVault public vault;

    /// @notice Referral storage contract
    IReferralStorage public referralStorage;

    /// @notice USDC token contract
    IERC20 public usdc;

    /// @notice Total claimed rebates per user: user => amount (6 decimals)
    mapping(address => uint256) public override claimedRebates;

    /// @notice Rebate nonces for replay protection: user => nonce
    mapping(address => uint256) public override rebateNonces;

    /// @notice EIP-712 Domain Separator
    bytes32 public DOMAIN_SEPARATOR;

    /// @notice EIP-712 Domain name, injected at deployment time
    string public NAME;

    /// @notice Claim type hash for EIP-712
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "ClaimRebate(address user,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    // ==================== Errors ====================

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when signature is expired
    error SignatureExpired(uint256 deadline, uint256 currentTime);

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when array lengths don't match
    error ArrayLengthMismatch(uint256 usersLength, uint256 amountsLength);

    /// @notice Thrown when domain name is empty
    error EmptyDomainName();

    /// @notice Thrown when domain version is empty
    error EmptyDomainVersion();

    // ==================== Initialization ====================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the rebate distributor contract
     * @param _usdc USDC token address
     * @param _vault Vault contract address
     * @param _backendSigner Backend signer address
     * @param _referralStorage Referral storage contract address (can be zero)
     * @param _domainName EIP-712 domain name, should come from backend env
     * @param _domainVersion EIP-712 domain version, should come from backend env
     * @param _owner Owner address with upgrade authority
     */
    function initialize(
        address _usdc,
        address _vault,
        address _backendSigner,
        address _referralStorage,
        string memory _domainName,
        string memory _domainVersion,
        address _owner
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        if (_usdc == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();
        if (_backendSigner == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (bytes(_domainName).length == 0) revert EmptyDomainName();
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        usdc = IERC20(_usdc);
        vault = IVault(_vault);
        backendSigner = _backendSigner;
        NAME = _domainName;
        VERSION = _domainVersion;

        if (_referralStorage != address(0)) {
            referralStorage = IReferralStorage(_referralStorage);
        }

        // Compute EIP-712 domain separator
        DOMAIN_SEPARATOR = SignatureVerifier.computeDomainSeparator(
            NAME,
            VERSION,
            block.chainid,
            address(this)
        );
    }

    /**
     * @notice Set EIP-712 domain version during an upgrade migration
     * @param _domainVersion EIP-712 domain version, should come from backend env
     */
    function reinitializeEip712DomainVersion(
        string memory _domainVersion
    ) external reinitializer(2) onlyOwner {
        if (bytes(_domainVersion).length == 0) revert EmptyDomainVersion();

        VERSION = _domainVersion;
        DOMAIN_SEPARATOR = SignatureVerifier.computeDomainSeparator(
            NAME,
            VERSION,
            block.chainid,
            address(this)
        );
    }

    // ==================== Claim Functions ====================

    /**
     * @notice Claim rebate (requires backend signature)
     * @dev Uses EIP-712 signature for authorization
     * @dev Implements nonce-based replay protection
     * @param amount Amount of USDC rebate to claim (6 decimals)
     * @param deadline Signature expiration timestamp
     * @param signature Backend signature for this claim
     */
    function claimRebate(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external override nonReentrant {
        // Validate deadline
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline, block.timestamp);
        }

        // Validate amount
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Get and increment nonce
        uint256 nonce = rebateNonces[msg.sender];
        rebateNonces[msg.sender] = nonce + 1;

        // Verify signature
        if (
            !SignatureVerifier.verifyClaimSignature(
                DOMAIN_SEPARATOR,
                msg.sender,
                amount,
                nonce,
                deadline,
                signature,
                backendSigner
            )
        ) {
            revert InvalidSignature();
        }

        // Update claimed amount
        claimedRebates[msg.sender] += amount;

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, amount);

        emit RebateClaimed(msg.sender, amount, nonce);
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Batch sync rebates (admin only)
     * @dev Distributes rebates to multiple users in a single transaction
     * @param users Array of user addresses
     * @param amounts Array of rebate amounts (6 decimals)
     * @param batchId Batch ID for tracking
     */
    function batchSyncRebates(
        address[] calldata users,
        uint256[] calldata amounts,
        uint256 batchId
    ) external override onlyOwner {
        if (users.length != amounts.length) {
            revert ArrayLengthMismatch(users.length, amounts.length);
        }

        uint256 totalAmount = 0;
        uint256 userCount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            if (amounts[i] > 0 && users[i] != address(0)) {
                // Update claimed amount
                claimedRebates[users[i]] += amounts[i];

                // Transfer USDC to user
                usdc.safeTransfer(users[i], amounts[i]);

                totalAmount += amounts[i];
                userCount++;
            }
        }

        emit RebateBatchSynced(batchId, totalAmount, userCount);
    }

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

    // ==================== Query Functions ====================

    /**
     * @notice Get user rebate information
     * @param user User address
     * @return claimed Total amount of rebates claimed
     * @return nonce Current rebate nonce
     * @return referralCode User's referral code
     * @return referrer Address of the referrer
     * @return tierLevel Tier level of the referrer
     */
    function getUserRebateInfo(
        address user
    )
        external
        view
        override
        returns (
            uint256 claimed,
            uint256 nonce,
            bytes32 referralCode,
            address referrer,
            uint256 tierLevel
        )
    {
        claimed = claimedRebates[user];
        nonce = rebateNonces[user];

        if (address(referralStorage) != address(0)) {
            referralCode = referralStorage.traderReferralCodes(user);
            if (referralCode != bytes32(0)) {
                referrer = referralStorage.codeOwners(referralCode);
                tierLevel = referralStorage.referrerTiers(referrer);
            }
        }
    }

    /**
     * @notice Get detailed referral configuration for a trader
     * @dev Uses on-chain tier config from referralStorage to compute rebate split
     * @param trader Trader address
     * @return code Referral code bound to the trader (bytes32)
     * @return referrer Affiliate / referrer address
     * @return totalRebateBps Total rebate rate in basis points (affiliate + trader discount)
     * @return traderDiscountBps Trader discount rate in basis points (portion of totalRebateBps)
     * @return affiliateRewardBps Affiliate reward rate in basis points (totalRebateBps - traderDiscountBps)
     */
    function getReferralInfo(
        address trader
    )
        external
        view
        returns (
            bytes32 code,
            address referrer,
            uint256 totalRebateBps,
            uint256 traderDiscountBps,
            uint256 affiliateRewardBps
        )
    {
        if (address(referralStorage) == address(0)) {
            return (bytes32(0), address(0), 0, 0, 0);
        }

        code = referralStorage.traderReferralCodes(trader);
        if (code == bytes32(0)) {
            return (bytes32(0), address(0), 0, 0, 0);
        }

        referrer = referralStorage.codeOwners(code);
        if (referrer == address(0)) {
            return (code, address(0), 0, 0, 0);
        }

        // Get tier configuration for the referrer
        uint256 tierLevel = referralStorage.referrerTiers(referrer);
        (uint256 totalRebate, uint256 discountShare) = referralStorage.tiers(
            tierLevel
        );

        // Allow custom discount share override per referrer if configured
        uint256 customDiscountShare = referralStorage.referrerDiscountShares(
            referrer
        );
        if (customDiscountShare != 0) {
            discountShare = customDiscountShare;
        }

        // totalRebate is in basis points (1e4 = 100%)
        // discountShare is also in basis points and represents the share of totalRebate for traders
        if (totalRebate == 0 || discountShare == 0) {
            return (code, referrer, 0, 0, 0);
        }

        totalRebateBps = totalRebate;
        traderDiscountBps = (totalRebate * discountShare) / BASIS_POINTS;
        affiliateRewardBps = totalRebateBps - traderDiscountBps;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    /// @notice EIP-712 Domain version, appended for upgrade-safe storage layout
    string public VERSION;

    uint256[49] private __gap;
}
