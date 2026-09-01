// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "../src/contracts/core/vault/Vault.sol";

/// @title VaultCriticalFixesTest
/// @notice Regression tests for the 2026-05-28 security audit fixes:
///   - CRITICAL-02: `withdraw` must NOT silently truncate user `_balances`
///     to zero while still transferring `amount`. A leaked or buggy
///     backendSigner cannot debt-fund a withdrawal from other users'
///     deposits — the on-chain `_balances[user]` is now the hard solvency
///     floor.
contract VaultCriticalFixesTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;

    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal user = address(0xCAFE);
    address internal otherUser = address(0xC0FFEE);

    event DepositPauseUpdated(bool paused);
    event WithdrawPauseUpdated(bool paused);

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);

        usdc = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (Vault.InitParams({
                usdc: address(usdc),
                backendSigner: backendSigner,
                referralStorage: referralStorage,
                domainName: "Primit Vault AVAX Fuji",
                domainVersion: "1.0.0",
                owner: admin,
                plpVault: address(0xDEAD1),
                liquidationManager: address(0xDEAD2),
                protocolFeeRecipient: address(0xDEAD3),
                dailySettlementCreditCap: 0,
                dailyUserSettlementCreditCap: 0
            }))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = Vault(address(proxy));
    }

    function _deposit(address account, uint256 amount) internal {
        usdc.mint(account, amount);
        vm.startPrank(account);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, bytes32(0));
        vm.stopPrank();
    }

    function _signWithdraw(address account, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                account,
                amount,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BACKEND_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============================================================
    // CRITICAL-02: withdraw must enforce _balances >= amount
    // ============================================================

    /// @notice The classic attack: legitimate user A deposits 100, malicious
    ///         backendSigner (or buggy backend) tries to sign a 1000 withdraw
    ///         for user B who only deposited 50. Pre-fix, this drained 950
    ///         from user A. Post-fix, it must revert.
    function test_CRITICAL02_withdrawRevertsWhenAmountExceedsChainBalance() public {
        // Two users so the contract has more pooled USDC than the attacker's _balances.
        _deposit(user, 50 ether);
        _deposit(otherUser, 100 ether);

        // Sanity: contract holds 150 ether of USDC, attacker's chain balance is 50 ether.
        assertEq(usdc.balanceOf(address(vault)), 150 ether);
        assertEq(vault.balances(user), 50 ether);

        uint256 deadline = block.timestamp + 300;
        uint256 abusiveAmount = 1_000 ether; // way beyond attacker's deposit
        bytes memory sig = _signWithdraw(user, abusiveAmount, vault.withdrawNonces(user), deadline);

        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, abusiveAmount, 50 ether));
        vm.prank(user);
        vault.withdraw(abusiveAmount, deadline, sig);

        // Post-condition: nothing moved.
        assertEq(usdc.balanceOf(address(vault)), 150 ether);
        assertEq(vault.balances(user), 50 ether);
        assertEq(vault.balances(otherUser), 100 ether);
        // Nonce was incremented before the signature check (the contract bumps
        // and then verifies); on revert the bump is rolled back, so still 0.
        assertEq(vault.withdrawNonces(user), 0);
    }

    /// @notice Happy path still works after the fix — withdraw == balance.
    function test_CRITICAL02_withdrawWorksAtExactChainBalance() public {
        _deposit(user, 100 ether);

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 100 ether, vault.withdrawNonces(user), deadline);

        vm.prank(user);
        vault.withdraw(100 ether, deadline, sig);

        assertEq(vault.balances(user), 0);
        assertEq(usdc.balanceOf(user), 100 ether);
        assertEq(vault.withdrawNonces(user), 1);
    }

    /// @notice Partial withdraw still works.
    function test_CRITICAL02_withdrawWorksBelowChainBalance() public {
        _deposit(user, 100 ether);

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 40 ether, vault.withdrawNonces(user), deadline);

        vm.prank(user);
        vault.withdraw(40 ether, deadline, sig);

        assertEq(vault.balances(user), 60 ether);
        assertEq(usdc.balanceOf(user), 40 ether);
    }

    /// @notice After settlePositionBalance credits PnL, the new chain balance
    ///         is the cap. This proves the documented backend flow still works:
    ///         backend MUST settlePositionBalance first, then sign withdraw.
    function test_CRITICAL02_withdrawHonorsCreditedPnl() public {
        address liquidationManager = address(0xA55E7);

        _deposit(user, 100 ether);
        // Pool extra USDC so the credit is backed.
        usdc.mint(address(vault), 50 ether);

        vm.prank(admin);
        vault.setLiquidationManager(liquidationManager);
        vm.prank(admin);
        vault.setDailySettlementCreditCap(50 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(50 ether);

        // Credit +50 PnL to user.
        vm.prank(liquidationManager);
        vault.settlePositionBalance(user, 50 ether, keccak256("credit"));
        assertEq(vault.balances(user), 150 ether);

        // settlePositionBalance bumped the nonce — pick it up for signing.
        uint256 currentNonce = vault.withdrawNonces(user);
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 150 ether, currentNonce, deadline);

        vm.prank(user);
        vault.withdraw(150 ether, deadline, sig);

        assertEq(vault.balances(user), 0);
        assertEq(usdc.balanceOf(user), 150 ether);
    }

    /// @notice The legacy institutional/market-maker accounting ABI is no
    ///         longer supported. Unknown selectors must fail rather than
    ///         silently creating an off-chain-style accounting balance.
    function test_institutionalAccountingAbiIsRemoved() public {
        address multisig = address(0xDEADBEEF);

        vm.startPrank(admin);
        (bool recordOk,) =
            address(vault).call(abi.encodeWithSignature("recordInstitutionalDeposit(address,uint256)", multisig, 1 ether));
        (bool withdrawOk,) =
            address(vault).call(abi.encodeWithSignature("withdrawInstitutional(address,uint256)", multisig, 1 ether));
        vm.stopPrank();

        assertFalse(recordOk);
        assertFalse(withdrawOk);
    }

    function test_ownerCanPauseDepositsWithoutPausingWithdrawals() public {
        _deposit(user, 100 ether);

        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositPauseUpdated(true);
        vm.prank(admin);
        vault.setDepositPaused(true);

        assertTrue(vault.depositPaused());
        assertFalse(vault.withdrawPaused());

        usdc.mint(user, 10 ether);
        vm.startPrank(user);
        usdc.approve(address(vault), 10 ether);
        vm.expectRevert(Vault.DepositsPaused.selector);
        vault.deposit(10 ether, bytes32(0));
        vm.stopPrank();

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 10 ether, vault.withdrawNonces(user), deadline);

        vm.prank(user);
        vault.withdraw(10 ether, deadline, sig);

        assertEq(vault.balances(user), 90 ether);
        assertEq(usdc.balanceOf(user), 20 ether);

        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositPauseUpdated(false);
        vm.prank(admin);
        vault.setDepositPaused(false);

        assertFalse(vault.depositPaused());
    }

    function test_ownerCanPauseWithdrawalsWithoutPausingDeposits() public {
        _deposit(user, 100 ether);

        vm.expectEmit(false, false, false, true, address(vault));
        emit WithdrawPauseUpdated(true);
        vm.prank(admin);
        vault.setWithdrawPaused(true);

        assertFalse(vault.depositPaused());
        assertTrue(vault.withdrawPaused());

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 10 ether, vault.withdrawNonces(user), deadline);

        vm.expectRevert(Vault.WithdrawalsPaused.selector);
        vm.prank(user);
        vault.withdraw(10 ether, deadline, sig);

        assertEq(vault.withdrawNonces(user), 0);
        assertEq(vault.balances(user), 100 ether);

        _deposit(user, 10 ether);
        assertEq(vault.balances(user), 110 ether);

        vm.expectEmit(false, false, false, true, address(vault));
        emit WithdrawPauseUpdated(false);
        vm.prank(admin);
        vault.setWithdrawPaused(false);

        assertFalse(vault.withdrawPaused());
    }

    function test_onlyOwnerCanToggleIndependentPauses() public {
        vm.expectRevert();
        vm.prank(user);
        vault.setDepositPaused(true);

        vm.expectRevert();
        vm.prank(user);
        vault.setWithdrawPaused(true);

        assertFalse(vault.depositPaused());
        assertFalse(vault.withdrawPaused());
    }

    // ============================================================
    // CertiK PRI-12 · withdrawAll drains dust below minWithdraw
    // ============================================================

    /// @notice The dust scenario: user's chain balance is smaller than
    ///         minWithdraw, so regular withdraw() reverts AmountBelowMinimum.
    ///         withdrawAll() must succeed and drain the balance to 0.
    function test_PRI12_withdrawAll_drains_dust_below_minWithdraw() public {
        // Set minWithdraw high enough that the dust below cannot be withdrawn normally.
        vm.prank(admin);
        vault.setMinWithdraw(10 ether);

        // Fund user 0.3 ether (dust: below 10 ether minWithdraw).
        usdc.mint(address(vault), 0.3 ether);
        // Raise settlement caps so the seeding credit path is not blocked (cap defaults to 0).
        vm.startPrank(admin);
        vault.setDailySettlementCreditCap(100 ether);
        vault.setDailyUserSettlementCreditCap(100 ether);
        vm.stopPrank();
        // Set _balances[user] = 0.3 ether directly via backend settlement path.
        vm.prank(backendSigner);
        vault.settlePositionBalance(user, int256(0.3 ether), keccak256("PRI12-seed"));

        assertEq(vault.balances(user), 0.3 ether);
        assertEq(usdc.balanceOf(user), 0);

        // Sanity: regular withdraw of the dust reverts under minWithdraw.
        uint256 deadline = block.timestamp + 300;
        uint256 nonce = vault.withdrawNonces(user);
        bytes memory dustSig = _signWithdraw(user, 0.3 ether, nonce, deadline);
        vm.expectRevert(abi.encodeWithSelector(Vault.AmountBelowMinimum.selector, 0.3 ether, 10 ether));
        vm.prank(user);
        vault.withdraw(0.3 ether, deadline, dustSig);

        // withdrawAll succeeds using a signature over the exact balance
        bytes memory allSig = _signWithdraw(user, 0.3 ether, nonce, deadline);
        vm.prank(user);
        vault.withdrawAll(deadline, allSig);

        assertEq(vault.balances(user), 0);
        assertEq(usdc.balanceOf(user), 0.3 ether);
        assertEq(vault.withdrawNonces(user), nonce + 1);
    }

    /// @notice withdrawAll on a zero balance must revert ZeroAmount (no fake success).
    function test_PRI12_withdrawAll_reverts_zero_balance() public {
        assertEq(vault.balances(user), 0);
        uint256 deadline = block.timestamp + 300;
        // Any signature works: the ZeroAmount check happens before signature verification.
        bytes memory sig = _signWithdraw(user, 0, vault.withdrawNonces(user), deadline);

        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(user);
        vault.withdrawAll(deadline, sig);
    }

    /// @notice withdrawAll must still enforce the backend signature — a bad signer reverts.
    function test_PRI12_withdrawAll_reverts_wrong_signer() public {
        _deposit(user, 5 ether);
        uint256 badKey = 0xDEADBEEF;
        uint256 deadline = block.timestamp + 300;
        uint256 nonce = vault.withdrawNonces(user);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                user, uint256(5 ether), nonce, deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(user);
        vault.withdrawAll(deadline, badSig);
    }

    /// @notice withdrawAll must reject an expired signature deadline.
    function test_PRI12_withdrawAll_reverts_expired_deadline() public {
        _deposit(user, 5 ether);
        uint256 deadline = block.timestamp; // exactly now
        uint256 nonce = vault.withdrawNonces(user);
        bytes memory sig = _signWithdraw(user, 5 ether, nonce, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(Vault.SignatureExpired.selector, deadline, deadline + 1));
        vm.prank(user);
        vault.withdrawAll(deadline, sig);
    }

    /// @notice withdrawAll must respect withdrawPaused.
    function test_PRI12_withdrawAll_reverts_when_withdraws_paused() public {
        _deposit(user, 5 ether);
        vm.prank(admin);
        vault.setWithdrawPaused(true);

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _signWithdraw(user, 5 ether, vault.withdrawNonces(user), deadline);

        vm.expectRevert(Vault.WithdrawalsPaused.selector);
        vm.prank(user);
        vault.withdrawAll(deadline, sig);
    }
}
