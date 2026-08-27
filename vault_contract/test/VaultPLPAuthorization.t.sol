// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @notice Vault.sol PLP 白名单授权升级 TDD 测试套
/// @dev D-PT-5:PLP 需通过 vault.debitFromUser / creditToUser 操作用户余额,
///      Vault 通过 plpVaultAddress + onlyPLP modifier 白名单授权 PLP 合约。
///      reinitializer(5)(前 4 个已用)完成一次性升级。
contract VaultPLPAuthorizationTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;
    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);

    // 本地 event 复刻(Foundry 惯用)
    event PLPAddressSet(address indexed plp);
    event BalanceDebitedByPLP(address indexed user, uint256 amount);
    event BalanceCreditedByPLP(address indexed user, uint256 amount);

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);

        usdc = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize, (address(usdc), backendSigner, referralStorage, "Primit Vault AVAX Fuji", "1.0.0", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = Vault(address(proxy));
    }

    // ================================================================
    // 🔴 RED #58: 未升级时 plpVaultAddress 默认为 0
    // ================================================================

    function test_plpVaultAddress_defaults_to_zero_before_upgrade() public {
        assertEq(vault.plpVaultAddress(), address(0));
    }

    // ================================================================
    // 🔴 RED #59: owner 调 reinitializeAddPLPAddress 后 plpVaultAddress 更新
    // ================================================================

    function test_reinitializeAddPLPAddress_sets_plp() public {
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);
        assertEq(vault.plpVaultAddress(), plp);
    }

    // ================================================================
    // 🔴 RED #60: debitFromUser 拒绝非 PLP 调用者(核心安全属性)
    // ================================================================

    function test_debitFromUser_reverts_non_plp() public {
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(Vault.OnlyPLP.selector);
        vault.debitFromUser(address(0xDEAD), 1e6);
    }

    /// @dev 帮助:让用户 deposit,建立 _balances 底
    function _mintAndDeposit(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, bytes32(0));
        vm.stopPrank();
    }

    // ================================================================
    // 🔴 RED #61: PLP 调 debitFromUser 减少用户 _balances
    // ================================================================

    // ================================================================
    // 🔴 RED #62: creditToUser 拒绝非 PLP 调用者
    // ================================================================

    function test_creditToUser_reverts_non_plp() public {
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(Vault.OnlyPLP.selector);
        vault.creditToUser(address(0xDEAD), 1e18);
    }

    function test_debitFromUser_decreases_user_balance() public {
        // 1. 用户存 1000 tokens(ERC20Mock 默认 18 decimals,Vault min >= 1e18)
        address user = address(0xC0FFEE);
        uint256 depositAmount = 1000 * 1e18;
        _mintAndDeposit(user, depositAmount);
        assertEq(vault.getBalance(user), depositAmount);

        // 2. Owner 授权 PLP
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        // 3. PLP 调 debit 扣 300
        vm.prank(plp);
        vault.debitFromUser(user, 300 * 1e18);

        // 4. 用户余额减少
        assertEq(vault.getBalance(user), 700 * 1e18);
    }

    // ================================================================
    // 🔴 RED #63: PLP 调 creditToUser 增加用户 _balances
    // ================================================================

    // ================================================================
    // 🔴 RED #64: reinitializeAddPLPAddress emit PLPAddressSet event
    // ================================================================

    function test_reinitializeAddPLPAddress_emits_event() public {
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(vault));
        emit PLPAddressSet(plp);
        vault.reinitializeAddPLPAddress(plp);
    }

    // ================================================================
    // 🔴 RED #66: creditToUser emit BalanceCreditedByPLP
    // ================================================================

    function test_creditToUser_emits_BalanceCreditedByPLP() public {
        address user = address(0xC0FFEE);
        _mintAndDeposit(user, 1000 * 1e18);
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        vm.prank(plp);
        vm.expectEmit(true, false, false, true, address(vault));
        emit BalanceCreditedByPLP(user, 55 * 1e18);
        vault.creditToUser(user, 55 * 1e18);
    }

    // ================================================================
    // 🔴 RED #65: debitFromUser emit BalanceDebitedByPLP
    // ================================================================

    function test_debitFromUser_emits_BalanceDebitedByPLP() public {
        address user = address(0xC0FFEE);
        _mintAndDeposit(user, 1000 * 1e18);
        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        vm.prank(plp);
        vm.expectEmit(true, false, false, true, address(vault));
        emit BalanceDebitedByPLP(user, 200 * 1e18);
        vault.debitFromUser(user, 200 * 1e18);
    }

    function test_creditToUser_increases_user_balance() public {
        address user = address(0xC0FFEE);
        // 先 deposit 建立 vault 上有 usdc 底
        _mintAndDeposit(user, 1000 * 1e18);

        address plp = address(0xCAFE1);
        vm.prank(admin);
        vault.reinitializeAddPLPAddress(plp);

        uint256 balanceBefore = vault.getBalance(user);
        vm.prank(plp);
        vault.creditToUser(user, 50 * 1e18);
        assertEq(vault.getBalance(user), balanceBefore + 50 * 1e18);
    }
}
