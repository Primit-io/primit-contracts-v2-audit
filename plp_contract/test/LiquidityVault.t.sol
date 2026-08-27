// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice PLP LiquidityVault TDD 测试套
/// @dev 严格 RED → GREEN → REFACTOR 循环。每个 test 单一行为,清晰命名。
/// @dev 合约实现基于 EarnProduct + OpenZeppelin,禁引入任何 GMX BUSL 代码。
/// @dev 最小 Vault mock,仅为 PLP 记录 debit/credit 调用
contract VaultMock {
    address public lastDebitedUser;
    uint256 public lastDebitedAmount;
    address public lastCreditedUser;
    uint256 public lastCreditedAmount;

    function debitFromUser(address user, uint256 amount) external {
        lastDebitedUser = user;
        lastDebitedAmount = amount;
    }

    function creditToUser(address user, uint256 amount) external {
        lastCreditedUser = user;
        lastCreditedAmount = amount;
    }
}

contract LiquidityVaultTest is Test {
    address constant USDC_MOCK = address(0xB01);
    address constant ADMIN = address(0xA01);
    address constant OPERATOR = address(0xA02);
    uint256 constant SIGNER_KEY = uint256(keccak256("PLP_TEST_SIGNER_KEY"));
    address SIGNER = vm.addr(SIGNER_KEY);
    address VAULT_MOCK; // 部署 mock 后填充

    function setUp() public {
        VAULT_MOCK = address(new VaultMock());
    }

    // 本地 event 复刻(Foundry 惯用法,供 vm.expectEmit 使用)
    event Deposited(address indexed user, uint8 tier, uint256 amount);
    event Withdrew(address indexed user, uint8 tier, uint256 sharesBurned, uint256 assetsReturned);
    event FeeShareApplied(uint256 amount);
    event MarketPnLApplied(int256 delta);

    /// @dev 帮助函数:用 SIGNER_KEY 签一笔 withdraw
    function _signWithdraw(
        LiquidityVault plp,
        address user,
        uint256 shares,
        uint8 tier,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(plp.WITHDRAW_TYPEHASH(), user, shares, tier, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", plp.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev 帮助函数:用 SIGNER_KEY 签一笔 deposit
    function _signDeposit(
        LiquidityVault plp,
        address user,
        uint256 amount,
        uint8 tier,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(plp.DEPOSIT_TYPEHASH(), user, amount, tier, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", plp.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev PRI-03 fix · 通过 UUPS proxy 部署 + initialize · 复刻主网真实拓扑
    function _deployPlp(
        address usdc,
        address vault,
        address admin,
        address operator,
        address signer
    ) internal returns (LiquidityVault) {
        LiquidityVault impl = new LiquidityVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                LiquidityVault.initialize,
                (usdc, vault, admin, operator, signer)
            )
        );
        return LiquidityVault(address(proxy));
    }

    function _deployPlpDefault() internal returns (LiquidityVault) {
        return _deployPlp(USDC_MOCK, VAULT_MOCK, ADMIN, OPERATOR, SIGNER);
    }

    /// @dev external wrapper · vm.expectRevert 只抓下一次 external call · CREATE opcode 内的 revert 需通过 this.xxx 冒泡才被识别
    function deployPlpExternal(
        address usdc,
        address vault,
        address admin,
        address operator,
        address signer
    ) external returns (LiquidityVault) {
        return _deployPlp(usdc, vault, admin, operator, signer);
    }

    // ================================================================
    // 🔴 RED #1: 部署标识 marker(D-PT-30 防钓鱼)
    // ================================================================

    /// @notice PLP v1 合约必须返回固定的部署 marker,前端首次连接校验
    function test_deploymentMarker_returns_v1_avax_mainnet() public {
        LiquidityVault plp = new LiquidityVault();
        bytes32 expected = keccak256(abi.encodePacked("PLP-V1-AVAX-MAINNET"));
        assertEq(plp.deploymentMarker(), expected);
    }

    // ================================================================
    // 🔴 RED #2: initialize 存储 USDC 地址
    // ================================================================

    /// @notice 初始化后 usdc() 返回构造时传入的地址
    function test_initialize_stores_usdc_address() public {
        LiquidityVault plp = _deployPlpDefault();
        assertEq(plp.usdc(), USDC_MOCK);
    }

    // ================================================================
    // 🔴 RED #3: initialize 不能重复调用
    // ================================================================

    function test_initialize_reverts_on_second_call() public {
        LiquidityVault plp = _deployPlpDefault();
        vm.expectRevert();
        plp.initialize(USDC_MOCK, VAULT_MOCK, ADMIN, OPERATOR, SIGNER);
    }

    // ================================================================
    // 🔴 RED #4: initialize 拒绝 zero USDC 地址
    // ================================================================

    function test_initialize_reverts_zero_usdc() public {
        vm.expectRevert(LiquidityVault.ZeroAddress.selector);
        this.deployPlpExternal(address(0), VAULT_MOCK, ADMIN, OPERATOR, SIGNER);
    }

    // ================================================================
    // 🔴 RED #5: initialize 存储 Vault 地址
    // ================================================================

    function test_initialize_stores_vault_address() public {
        LiquidityVault plp = _deployPlpDefault();
        assertEq(plp.vault(), VAULT_MOCK);
    }

    // ================================================================
    // 🔴 RED #6: initialize 拒绝 zero Vault 地址
    // ================================================================

    function test_initialize_reverts_zero_vault() public {
        vm.expectRevert(LiquidityVault.ZeroAddress.selector);
        this.deployPlpExternal(USDC_MOCK, address(0), ADMIN, OPERATOR, SIGNER);
    }

    /// @notice CertiK PRI-10 · zero admin at init must revert
    function test_PRI10_initialize_reverts_zero_admin() public {
        vm.expectRevert(LiquidityVault.ZeroAddress.selector);
        this.deployPlpExternal(USDC_MOCK, VAULT_MOCK, address(0), OPERATOR, SIGNER);
    }

    /// @notice CertiK PRI-10 · zero operator at init must revert
    function test_PRI10_initialize_reverts_zero_operator() public {
        vm.expectRevert(LiquidityVault.ZeroAddress.selector);
        this.deployPlpExternal(USDC_MOCK, VAULT_MOCK, ADMIN, address(0), SIGNER);
    }

    /// @notice CertiK PRI-10 · zero signer at init must revert
    function test_PRI10_initialize_reverts_zero_signer() public {
        vm.expectRevert(LiquidityVault.ZeroAddress.selector);
        this.deployPlpExternal(USDC_MOCK, VAULT_MOCK, ADMIN, OPERATOR, address(0));
    }

    // ================================================================
    // 🔴 RED #7: TIER_3D 常量 = 3(Junior 3 天档标识)
    // ================================================================

    function test_TIER_3D_equals_3() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(uint256(plp.TIER_3D()), 3);
    }

    // ================================================================
    // 🔴 RED #8: TIER_7D 常量 = 7(Junior 7 天档标识)
    // ================================================================

    function test_TIER_7D_equals_7() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(uint256(plp.TIER_7D()), 7);
    }

    // ================================================================
    // 🔴 RED #9: WARMUP_DURATION = 30 分钟(D-LP-12 入池冷却)
    // ================================================================

    function test_WARMUP_DURATION_equals_30_minutes() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.WARMUP_DURATION(), 30 minutes);
    }

    // ================================================================
    // 🔴 RED #10: MIN_DEPOSIT = 1 USDC.e(D6 · 2026-07-20 dev 环境改为 1u
    //   便于小额端到端 smoke;v1.1 灰度前恢复到产品定稿值)
    // ================================================================

    function test_MIN_DEPOSIT_equals_1_usdc() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.MIN_DEPOSIT(), 100 * 1e6);
    }

    // ================================================================
    // 🔴 RED #11: TIER_3D_WEIGHT_BP = 8500(D-LP-16,3d 收益权重 0.85)
    // ================================================================

    function test_TIER_3D_WEIGHT_BP_equals_8500() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.TIER_3D_WEIGHT_BP(), 8500);
    }

    // ================================================================
    // 🔴 RED #12: TIER_7D_WEIGHT_BP = 10000(D-LP-16,7d 收益权重 1.00)
    // ================================================================

    function test_TIER_7D_WEIGHT_BP_equals_10000() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.TIER_7D_WEIGHT_BP(), 10000);
    }

    // ================================================================
    // 🔴 RED #13: PERFORMANCE_FEE_BP = 1000(D-LP-7,10% profit → Buffer Pool)
    // ================================================================

    function test_PERFORMANCE_FEE_BP_equals_1000() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.PERFORMANCE_FEE_BP(), 1000);
    }

    // ================================================================
    // 🔴 RED #14: nonces(user) 默认为 0(EIP-712 反重放,D-PLP-EARN-02)
    // ================================================================

    function test_nonce_defaults_to_zero_for_new_user() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.nonces(address(0x1234)), 0);
    }

    // ================================================================
    // 🔴 RED #15: DEPOSIT_TYPEHASH 固定值(EIP-712 struct hash,防跨合约重放)
    // ================================================================

    function test_DEPOSIT_TYPEHASH_matches_eip712_signature() public {
        LiquidityVault plp = new LiquidityVault();
        bytes32 expected = keccak256(
            "PLPDeposit(address user,uint256 amount,uint8 tier,uint256 nonce,uint256 deadline)"
        );
        assertEq(plp.DEPOSIT_TYPEHASH(), expected);
    }

    // ================================================================
    // 🔴 RED #16: 初始化后 paused() 默认 false
    // ================================================================

    function test_paused_is_false_after_init() public {
        LiquidityVault plp = _deployPlpDefault();
        assertFalse(plp.paused());
    }

    // ================================================================
    // 🔴 RED #17: ADMIN_ROLE 常量 = keccak256("ADMIN_ROLE")(D-PT-27)
    // ================================================================

    function test_ADMIN_ROLE_hash() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
    }

    // ================================================================
    // 🔴 RED #18: OPERATOR_ROLE 常量(D-PT-27,触发 apply_market_pnl / fee_share 结算)
    // ================================================================

    function test_OPERATOR_ROLE_hash() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.OPERATOR_ROLE(), keccak256("OPERATOR_ROLE"));
    }

    // ================================================================
    // 🔴 RED #19: SIGNER_ROLE 常量(D-PT-27,EIP-712 deposit/withdraw 签名验证者)
    // ================================================================

    function test_SIGNER_ROLE_hash() public {
        LiquidityVault plp = new LiquidityVault();
        assertEq(plp.SIGNER_ROLE(), keccak256("SIGNER_ROLE"));
    }

    // ================================================================
    // 🔴 RED #20: initialize 授予 admin 的 ADMIN_ROLE
    // ================================================================

    function test_initialize_grants_admin_role_to_admin() public {
        LiquidityVault plp = _deployPlpDefault();
        assertTrue(plp.hasRole(plp.ADMIN_ROLE(), ADMIN));
    }

    // ================================================================
    // 🔴 RED #21: initialize 授予 operator 的 OPERATOR_ROLE
    // ================================================================

    function test_initialize_grants_operator_role_to_operator() public {
        LiquidityVault plp = _deployPlpDefault();
        assertTrue(plp.hasRole(plp.OPERATOR_ROLE(), OPERATOR));
    }

    // ================================================================
    // 🔴 RED #22: initialize 授予 signer 的 SIGNER_ROLE
    // ================================================================

    function test_initialize_grants_signer_role_to_signer() public {
        LiquidityVault plp = _deployPlpDefault();
        assertTrue(plp.hasRole(plp.SIGNER_ROLE(), SIGNER));
    }

    // ================================================================
    // 🔴 RED #23: deposit 拒绝非法 tier(除 3d / 7d 外)
    // ================================================================

    function test_deposit_reverts_invalid_tier() public {
        LiquidityVault plp = _deployPlpDefault();
        uint8 invalidTier = 5;
        uint256 amount = 100 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = "";
        vm.expectRevert(LiquidityVault.InvalidTier.selector);
        plp.deposit(amount, invalidTier, deadline, sig);
    }

    // ================================================================
    // 🔴 RED #24: deposit 拒绝 amount < MIN_DEPOSIT
    // ================================================================

    function test_deposit_reverts_amount_below_min() public {
        LiquidityVault plp = _deployPlpDefault();
        uint256 tooSmall = 99_999_999; // < 100e6,低于 v1 生产 MIN_DEPOSIT = 100u
        uint256 deadline = block.timestamp + 1 hours;
        uint8 tier3d = plp.TIER_3D(); // 先取,避免 vm.expectRevert 被 staticcall 消费
        vm.expectRevert(LiquidityVault.AmountBelowMin.selector);
        plp.deposit(tooSmall, tier3d, deadline, "");
    }

    // ================================================================
    // 🔴 RED #25: deposit 拒绝过期 deadline
    // ================================================================

    function test_deposit_reverts_expired_deadline() public {
        LiquidityVault plp = _deployPlpDefault();
        vm.warp(1_000_000); // 设时间基线
        uint256 expiredDeadline = 999_999; // 已过
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        vm.expectRevert(LiquidityVault.DeadlineExpired.selector);
        plp.deposit(amount, tier3d, expiredDeadline, "");
    }

    // ================================================================
    // 🔴 RED #26: deposit 在合约 paused 时 revert
    // ================================================================

    function test_deposit_reverts_when_paused() public {
        LiquidityVault plp = _deployPlpDefault();

        // ADMIN pause 合约
        vm.prank(ADMIN);
        plp.pause();

        uint256 amount = 100 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        uint8 tier3d = plp.TIER_3D();
        // OZ Pausable 抛出 EnforcedPause() 错误
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        plp.deposit(amount, tier3d, deadline, "");
    }

    // ================================================================
    // 🔴 RED #27: EIP-712 domain separator 初始化后可读
    // ================================================================

    function test_domain_separator_readable_after_init() public {
        LiquidityVault plp = _deployPlpDefault();
        // domain separator 应该非零(证明 EIP712 已初始化)
        assertTrue(plp.DOMAIN_SEPARATOR() != bytes32(0));
    }

    // ================================================================
    // 🔴 RED #28: deposit 拒绝错误签名者(非 SIGNER_ROLE)的签名
    // ================================================================

    function test_deposit_reverts_wrong_signer() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;

        // 用一个没有 SIGNER_ROLE 的私钥签
        uint256 attackerKey = 0xBADBADBAD;
        bytes32 structHash = keccak256(
            abi.encode(plp.DEPOSIT_TYPEHASH(), user, amount, tier3d, uint256(0), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", plp.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(LiquidityVault.InvalidSignature.selector);
        plp.deposit(amount, tier3d, deadline, badSig);
    }

    // ================================================================
    // 🔴 RED #29: 有效签名 + 正确 nonce → deposit 成功递增 nonce
    // ================================================================

    function test_deposit_valid_signature_increments_nonce() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;

        // SIGNER 私钥签名
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        assertEq(plp.nonces(user), 0);
        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, sig);
        assertEq(plp.nonces(user), 1);
    }

    // ================================================================
    // 🔴 RED #30: deposit emit Deposited(user, tier, amount) 事件
    // ================================================================

    function test_deposit_emits_Deposited_event() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        vm.prank(user);
        vm.expectEmit(true, false, false, true, address(plp));
        emit Deposited(user, tier3d, amount);
        plp.deposit(amount, tier3d, deadline, sig);
    }

    // ================================================================
    // 🔴 RED #31: plpShares(user, tier) 默认为 0
    // ================================================================

    function test_plpShares_defaults_to_zero_for_new_user() public {
        LiquidityVault plp = _deployPlpDefault();
        assertEq(plp.plpShares(address(0xBEEF), 3), 0);
    }

    // ================================================================
    // 🔴 RED #32: deposit 后 plpShares[user][tier] 增加 amount(v1 简化 1:1)
    // ================================================================

    function test_deposit_increases_plpShares() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, sig);

        assertEq(plp.plpShares(user, tier3d), amount);
    }

    // ================================================================
    // 🔴 RED #33: deposit 后 lastDepositAt[user][tier] = block.timestamp
    // ================================================================

    function test_deposit_updates_lastDepositAt() public {
        LiquidityVault plp = _deployPlpDefault();

        vm.warp(2_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, sig);

        assertEq(plp.lastDepositAt(user, tier3d), 2_000_000);
    }

    // ================================================================
    // 🔴 RED #34: totalAssets 初始化为 0
    // ================================================================

    function test_totalAssets_defaults_to_zero_after_init() public {
        LiquidityVault plp = _deployPlpDefault();
        assertEq(plp.totalAssets(), 0);
    }

    // ================================================================
    // 🔴 RED #35: deposit 增加 totalAssets 全局池资产
    // ================================================================

    function test_deposit_increases_totalAssets() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, sig);

        assertEq(plp.totalAssets(), amount);
    }

    // ================================================================
    // 🔴 RED #36: deposit 调用 vault.debitFromUser(user, amount)
    // ================================================================

    function test_deposit_calls_vault_debitFromUser() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signDeposit(plp, user, amount, tier3d, 0, deadline);

        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, sig);

        VaultMock vm_ = VaultMock(VAULT_MOCK);
        assertEq(vm_.lastDebitedUser(), user);
        assertEq(vm_.lastDebitedAmount(), amount);
    }

    // ================================================================
    // 🔴 RED #37: withdraw 拒绝非法 tier
    // ================================================================

    function test_withdraw_reverts_invalid_tier() public {
        LiquidityVault plp = _deployPlpDefault();
        uint8 invalidTier = 5;
        uint256 shares = 100 * 1e6;
        uint256 deadline = block.timestamp + 1 hours;
        vm.expectRevert(LiquidityVault.InvalidTier.selector);
        plp.withdraw(shares, invalidTier, deadline, "");
    }

    // ================================================================
    // 🔴 RED #38: withdraw 拒绝 shares 超过用户持有(未持有任何 shares)
    // ================================================================

    function test_withdraw_reverts_insufficient_shares() public {
        LiquidityVault plp = _deployPlpDefault();

        address user = address(0xBEEF);
        uint8 tier3d = plp.TIER_3D();
        uint256 requestShares = 1;
        uint256 deadline = block.timestamp + 1 hours;
        vm.prank(user);
        vm.expectRevert(LiquidityVault.InsufficientShares.selector);
        plp.withdraw(requestShares, tier3d, deadline, "");
    }

    // ================================================================
    // 🔴 RED #39: withdraw 拒绝锁定期未到(3d 档存后 2 天想取)
    // ================================================================

    function test_withdraw_reverts_lockup_not_expired() public {
        LiquidityVault plp = _deployPlpDefault();

        // 先存 100 USDC 到 3d 档
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory depositSig = _signDeposit(plp, user, amount, tier3d, 0, deadline);
        vm.prank(user);
        plp.deposit(amount, tier3d, deadline, depositSig);

        // D6.3 dev · lockup = tier * 30 seconds = 90s for tier 3
        // 60 秒后想取(仍在 90s lockup 内)· 硬编 deadline 避 via_ir CSE
        vm.warp(1_000_000 + 1 days);
        uint256 withdrawDeadline = 1_000_000 + 1 days + 1 hours;
        vm.prank(user);
        vm.expectRevert(LiquidityVault.LockupNotExpired.selector);
        plp.withdraw(amount, tier3d, withdrawDeadline, "");
    }

    // ================================================================
    // 🔴 RED #40: withdraw 拒绝过期 deadline(签名过期)
    // ================================================================

    function test_withdraw_reverts_expired_deadline() public {
        LiquidityVault plp = _deployPlpDefault();

        // 存 → 等锁定期过 → withdraw 但 deadline 已过
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 depDeadline = block.timestamp + 1 hours;
        bytes memory depositSig = _signDeposit(plp, user, amount, tier3d, 0, depDeadline);
        vm.prank(user);
        plp.deposit(amount, tier3d, depDeadline, depositSig);

        vm.warp(1_000_000 + 4 days); // 锁定期过
        uint256 expiredDeadline = 999_999; // 早于当前 block.timestamp
        vm.prank(user);
        vm.expectRevert(LiquidityVault.DeadlineExpired.selector);
        plp.withdraw(amount, tier3d, expiredDeadline, "");
    }

    // ================================================================
    // 🔴 RED #41: WITHDRAW_TYPEHASH 固定值(EIP-712 反跨函数重放)
    // ================================================================

    function test_WITHDRAW_TYPEHASH_matches_eip712_signature() public {
        LiquidityVault plp = new LiquidityVault();
        bytes32 expected = keccak256(
            "PLPWithdraw(address user,uint256 shares,uint8 tier,uint256 nonce,uint256 deadline)"
        );
        assertEq(plp.WITHDRAW_TYPEHASH(), expected);
    }

    // ================================================================
    // 🔴 RED #42: withdraw 错误签名者 → InvalidSignature
    // ================================================================

    function test_withdraw_reverts_wrong_signer() public {
        LiquidityVault plp = _deployPlpDefault();

        // deposit 前置
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 depDeadline = block.timestamp + 1 hours;
        bytes memory depositSig = _signDeposit(plp, user, amount, tier3d, 0, depDeadline);
        vm.prank(user);
        plp.deposit(amount, tier3d, depDeadline, depositSig);

        // 锁定期过
        vm.warp(1_000_000 + 4 days);
        // 硬编码 wdDeadline:solc via_ir + optimizer 会 CSE 掉多次 block.timestamp 读取
        uint256 wdDeadline = 1_000_000 + 4 days + 1 hours;

        // 用非 SIGNER_ROLE 私钥签 withdraw
        uint256 attackerKey = 0xBADBADBAD;
        bytes32 structHash = keccak256(
            abi.encode(plp.WITHDRAW_TYPEHASH(), user, amount, tier3d, uint256(1), wdDeadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", plp.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(LiquidityVault.InvalidSignature.selector);
        plp.withdraw(amount, tier3d, wdDeadline, badSig);
    }

    // ================================================================
    // 🔴 RED #45: applyFeeShare 拒绝非 OPERATOR_ROLE(否则任何人可给自己塞钱)
    // ================================================================

    function test_applyFeeShare_reverts_non_operator() public {
        LiquidityVault plp = _deployPlpDefault();

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert(); // OZ AccessControlUnauthorizedAccount
        plp.applyFeeShare(1_000_000);
    }

    // ================================================================
    // 🔴 RED #46: applyFeeShare emit FeeShareApplied(amount) 事件
    // ================================================================

    function test_applyFeeShare_emits_event() public {
        LiquidityVault plp = _deployPlpDefault();

        uint256 fee = 3_500_000;
        vm.prank(OPERATOR);
        vm.expectEmit(false, false, false, true, address(plp));
        emit FeeShareApplied(fee);
        plp.applyFeeShare(fee);
    }

    // ================================================================
    // 🔴 RED #48: applyMarketPnL emit MarketPnLApplied(delta) 事件
    // ================================================================

    function test_applyMarketPnL_emits_event() public {
        LiquidityVault plp = _deployPlpDefault();

        int256 pnl = 7 * int256(1e6);
        vm.prank(OPERATOR);
        vm.expectEmit(false, false, false, true, address(plp));
        emit MarketPnLApplied(pnl);
        plp.applyMarketPnL(pnl);
    }

    // ================================================================
    // 🔴 RED #47: OPERATOR 调用 applyMarketPnL(正 pnl)增加 totalAssets
    // ================================================================

    function test_applyMarketPnL_positive_increases_totalAssets() public {
        LiquidityVault plp = _deployPlpDefault();

        // 有一笔 100 USDC 池底
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        bytes memory depSig = _signDeposit(plp, user, amount, tier3d, 0, 1_000_000 + 1 hours);
        vm.prank(user);
        plp.deposit(amount, tier3d, 1_000_000 + 1 hours, depSig);

        // OPERATOR 结算做市赚 10 USDC
        int256 pnl = 10 * 1e6;
        vm.prank(OPERATOR);
        plp.applyMarketPnL(pnl);

        assertEq(plp.totalAssets(), amount + uint256(pnl));
    }

    // ================================================================
    // 🔴 RED #44: OPERATOR 调用 applyFeeShare 增加 totalAssets
    // ================================================================

    function test_applyFeeShare_increases_totalAssets() public {
        LiquidityVault plp = _deployPlpDefault();

        // 用户先存 100 USDC(否则 totalAssets 起点是 0,加 fee 也看得出来但更真实)
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        bytes memory depSig = _signDeposit(plp, user, amount, tier3d, 0, 1_000_000 + 1 hours);
        vm.prank(user);
        plp.deposit(amount, tier3d, 1_000_000 + 1 hours, depSig);

        assertEq(plp.totalAssets(), amount);

        // OPERATOR 注入手续费分成 5 USDC
        uint256 fee = 5 * 1e6;
        vm.prank(OPERATOR);
        plp.applyFeeShare(fee);

        assertEq(plp.totalAssets(), amount + fee);
    }

    // ================================================================
    // 🔴 RED #43: withdraw 成功 → shares 减 / totalAssets 减 / nonce++ / vault.credit / emit
    // ================================================================

    function test_withdraw_success_full_flow() public {
        LiquidityVault plp = _deployPlpDefault();

        // 1. deposit 100 USDC to 3d
        vm.warp(1_000_000);
        address user = address(0xBEEF);
        uint256 amount = 100 * 1e6;
        uint8 tier3d = plp.TIER_3D();
        uint256 depDeadline = 1_000_000 + 1 hours;
        bytes memory depSig = _signDeposit(plp, user, amount, tier3d, 0, depDeadline);
        vm.prank(user);
        plp.deposit(amount, tier3d, depDeadline, depSig);

        // 2. warp past lockup
        vm.warp(1_000_000 + 4 days);
        uint256 wdDeadline = 1_000_000 + 4 days + 1 hours;

        // 3. sign withdraw
        bytes memory wdSig = _signWithdraw(plp, user, amount, tier3d, 1, wdDeadline);

        // 4. state before
        assertEq(plp.plpShares(user, tier3d), amount);
        assertEq(plp.totalAssets(), amount);
        assertEq(plp.nonces(user), 1);

        // 5. expect Withdrew event
        vm.expectEmit(true, false, false, true, address(plp));
        emit Withdrew(user, tier3d, amount, amount); // v1 简化:assetsReturned == shares

        vm.prank(user);
        plp.withdraw(amount, tier3d, wdDeadline, wdSig);

        // 6. state after
        assertEq(plp.plpShares(user, tier3d), 0);
        assertEq(plp.totalAssets(), 0);
        assertEq(plp.nonces(user), 2);

        // 7. vault credit was called
        VaultMock v_ = VaultMock(VAULT_MOCK);
        assertEq(v_.lastCreditedUser(), user);
        assertEq(v_.lastCreditedAmount(), amount);
    }

    /// @notice CertiK PRI-03 · Unprotected Upgradeable Contract
    /// @dev 直接部署一份未 proxy 包装的实现合约 · 期望 initialize() 在 constructor 里已被 _disableInitializers 锁定 · 任何后续调用都必须 revert(InvalidInitialization)
    function test_implementation_initialize_reverts_disabled() public {
        LiquidityVault impl = new LiquidityVault();
        // OpenZeppelin v5 Initializable: 已 disable 的实现调 initialize 时 revert InvalidInitialization()
        vm.expectRevert(bytes4(keccak256("InvalidInitialization()")));
        impl.initialize(USDC_MOCK, VAULT_MOCK, ADMIN, OPERATOR, SIGNER);
    }
}
