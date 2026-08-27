// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Vault 白名单授权接口(D-PT-5),PLP 用此扣减用户主账户余额
interface IVaultDebit {
    function debitFromUser(address user, uint256 amount) external;
    function creditToUser(address user, uint256 amount) external;
}

/// @title  LiquidityVault
/// @notice Primit Liquidity Provider (PLP) 主合约
/// @dev    独立编写,不含任何 GMX BUSL 代码。参考 EarnProduct + OpenZeppelin。
contract LiquidityVault is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    // ========== 权限 role ==========
    /// @notice 管理员 role(D-PT-27,pause/unpause/参数升级)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice 运营 role(D-PT-27,触发做市 pnl 结算 / fee_share 应用)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice 签名者 role(D-PT-27,EIP-712 deposit/withdraw 签名验证)
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // ========== 常量 ==========
    /// @notice Junior 3 天档 tier 标识
    uint8 public constant TIER_3D = 3;
    /// @notice Junior 7 天档 tier 标识
    uint8 public constant TIER_7D = 7;
    /// @notice 入池冷却期(D-LP-12 反抢跑,新入金 30 分钟内不参与做市不算净值)
    uint256 public constant WARMUP_DURATION = 30 minutes;
    /// @notice 最小起投额(D-LP-6,USDC 6 decimals,$100 = 100e6)
    uint256 public constant MIN_DEPOSIT = 100 * 1e6;
    /// @notice 3 天档收益权重(D-LP-16,bp = 万分之)
    uint16 public constant TIER_3D_WEIGHT_BP = 8500;
    /// @notice 7 天档收益权重(D-LP-16,基准 100%)
    uint16 public constant TIER_7D_WEIGHT_BP = 10000;
    /// @notice Performance fee 比例(D-LP-7,盈利 10% 归 Buffer Pool)
    uint16 public constant PERFORMANCE_FEE_BP = 1000;

    // ========== EIP-712 typehash ==========
    /// @notice PLPDeposit 结构 hash(EIP-712 反跨合约重放)
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256(
        "PLPDeposit(address user,uint256 amount,uint8 tier,uint256 nonce,uint256 deadline)"
    );
    /// @notice PLPWithdraw 结构 hash(反跨函数重放:不能用 deposit 签名去 withdraw)
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256(
        "PLPWithdraw(address user,uint256 shares,uint8 tier,uint256 nonce,uint256 deadline)"
    );

    // ========== 错误 ==========
    error ZeroAddress();
    error InvalidTier();
    error AmountBelowMin();
    error DeadlineExpired();
    error InvalidSignature();
    error InsufficientShares();
    error LockupNotExpired();

    // ========== 事件 ==========
    event Deposited(address indexed user, uint8 tier, uint256 amount);
    event Withdrew(address indexed user, uint8 tier, uint256 sharesBurned, uint256 assetsReturned);
    event FeeShareApplied(uint256 amount);
    event MarketPnLApplied(int256 delta);

    // ========== 状态 ==========
    address public usdc;
    address public vault;

    /// @notice EIP-712 反重放 nonce(D-PLP-EARN-02,单调递增,比 usedSignatures gas 更优)
    mapping(address => uint256) public nonces;

    /// @notice 用户份额记账 user => tier => shares(v1 简化:shares = amount,NAV 视为 1)
    mapping(address => mapping(uint8 => uint256)) public plpShares;

    /// @notice 用户在某 tier 上最后一次 deposit 的时间戳(锁定期起点)
    mapping(address => mapping(uint8 => uint256)) public lastDepositAt;

    /// @notice 全局总资产(USDC.e 6 decimals),做市 pnl 结算时更新
    uint256 public totalAssets;

    /// @notice 锁定实现合约的初始化 · 只允许通过 UUPS proxy delegatecall 走 initialize · 阻止攻击者直接抢占实现的 admin 角色
    /// @dev CertiK PRI-03 · Unprotected Upgradeable Contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 部署 marker,前端首次连接校验防钓鱼(D-PT-30)
    function deploymentMarker() external pure returns (bytes32) {
        return keccak256(abi.encodePacked("PLP-V1-AVAX-MAINNET"));
    }

    /// @notice 初始化 PLP 合约,注入依赖地址(只能调用一次)
    /// @param _usdc  USDC.e 代币合约地址
    /// @param _vault 主 Vault 合约地址(用于 debit/credit 用户余额)
    function initialize(
        address _usdc,
        address _vault,
        address _admin,
        address _operator,
        address _signer
    ) external initializer {
        if (_usdc == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();
        // CertiK PRI-10 · Missing Zero Address Validation
        // Reject zero-address role holders at initialize time to prevent
        // a mis-configured proxy from silently landing with orphaned roles
        // (deposits / withdraws would still work but no ADMIN could pause,
        // no OPERATOR could settle PnL, no SIGNER could co-sign flows).
        if (_admin == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();
        if (_signer == address(0)) revert ZeroAddress();
        __Pausable_init();
        __AccessControl_init();
        __EIP712_init("PrimitLiquidityProvider", "1");
        __UUPSUpgradeable_init();
        usdc = _usdc;
        vault = _vault;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(SIGNER_ROLE, _signer);
    }

    /// @notice UUPS upgrade authorization gate · only ADMIN_ROLE can call upgradeToAndCall.
    /// @dev In production ADMIN_ROLE is granted to the multisig only.
    function _authorizeUpgrade(address /* newImpl */) internal override onlyRole(ADMIN_ROLE) {}

    // ================================================================
    // 用户操作
    // ================================================================

    /// @notice 用户存入 PLP
    /// @param amount   存入金额(USDC.e 6 decimals)
    /// @param tier     锁定档次(必须是 TIER_3D=3 或 TIER_7D=7)
    /// @param deadline 签名有效期
    /// @param signature EIP-712 后端签名
    function deposit(uint256 amount, uint8 tier, uint256 deadline, bytes calldata signature) external whenNotPaused {
        if (tier != TIER_3D && tier != TIER_7D) revert InvalidTier();
        if (amount < MIN_DEPOSIT) revert AmountBelowMin();
        if (block.timestamp > deadline) revert DeadlineExpired();

        bytes32 structHash = keccak256(
            abi.encode(DEPOSIT_TYPEHASH, msg.sender, amount, tier, nonces[msg.sender], deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        if (!hasRole(SIGNER_ROLE, signer)) revert InvalidSignature();

        nonces[msg.sender]++;
        plpShares[msg.sender][tier] += amount;
        lastDepositAt[msg.sender][tier] = block.timestamp;
        totalAssets += amount;
        IVaultDebit(vault).debitFromUser(msg.sender, amount);
        emit Deposited(msg.sender, tier, amount);
    }

    // ================================================================
    // 管理员操作
    // ================================================================

    /// @notice 用户取出 PLP 份额
    /// @param shares 要 burn 的份额数量
    /// @param tier 锁定档次(必须是 TIER_3D=3 或 TIER_7D=7)
    /// @param deadline 签名有效期
    /// @param signature EIP-712 后端签名
    function withdraw(uint256 shares, uint8 tier, uint256 deadline, bytes calldata signature) external whenNotPaused {
        if (tier != TIER_3D && tier != TIER_7D) revert InvalidTier();
        if (plpShares[msg.sender][tier] < shares) revert InsufficientShares();

        // v1 生产 · lockup = tier × 1 days · Tier 3 = 3 days · Tier 7 = 7 days
        uint256 lockDuration = uint256(tier) * 1 days;
        if (block.timestamp < lastDepositAt[msg.sender][tier] + lockDuration) revert LockupNotExpired();
        if (block.timestamp > deadline) revert DeadlineExpired();

        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TYPEHASH, msg.sender, shares, tier, nonces[msg.sender], deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        if (!hasRole(SIGNER_ROLE, signer)) revert InvalidSignature();

        nonces[msg.sender]++;
        plpShares[msg.sender][tier] -= shares;
        // v1 简化:NAV=1,assetsReturned = shares(1:1)。后续 v1.1 引入 navPerShare 时改此处
        uint256 assetsReturned = shares;
        totalAssets -= assetsReturned;
        IVaultDebit(vault).creditToUser(msg.sender, assetsReturned);
        emit Withdrew(msg.sender, tier, shares, assetsReturned);
    }

    /// @notice OPERATOR 注入手续费分成到 PLP 池(D-LP-4 手续费分成)
    /// @param amount USDC.e 数量(6 decimals),由 backend fee_share_settler 定期结算触发
    function applyFeeShare(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        totalAssets += amount;
        emit FeeShareApplied(amount);
    }

    /// @notice OPERATOR 结算做市 PnL(D-LP-8 sidecar backend 触发)
    /// @param delta 正值增加 totalAssets,负值减少
    function applyMarketPnL(int256 delta) external onlyRole(OPERATOR_ROLE) {
        if (delta >= 0) {
            totalAssets += uint256(delta);
        } else {
            uint256 loss = uint256(-delta);
            totalAssets = loss >= totalAssets ? 0 : totalAssets - loss;
        }
        emit MarketPnLApplied(delta);
    }

    /// @notice 紧急暂停(D-LP-9,v1 简化为 admin 手动触发)
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice EIP-712 domain separator(D-PT-28,前端签名校验用)
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
