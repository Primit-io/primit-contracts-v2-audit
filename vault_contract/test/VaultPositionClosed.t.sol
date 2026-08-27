// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "../src/contracts/core/vault/Vault.sol";
import "../src/contracts/libraries/SignatureVerifier.sol";

/// @title VaultPositionClosedTest
/// @notice Covers `recordPositionClose` — the user-submitted, backend-signed
///         audit-log hook (2026-05-22 redesign: user pays gas, backend signs
///         off-chain to prove parameters).
///
/// Invariants tested:
///   - Emits `PositionClosed` with all six fields exactly as passed when
///     called by the user with a valid backend signature.
///   - Reverts `InvalidSignature` when signature is from a non-backend signer.
///   - Reverts `InvalidSignature` when any signed field is tampered with.
///   - Reverts `SignatureExpired` after deadline.
///   - Reverts `UserMismatch` when msg.sender != user param.
///   - Reverts `ZeroAddress` when user is zero.
///   - Reverts `InvalidSignatureLength` when signature is wrong size.
///   - Touches NO balance / total / nonce state (audit-only).
///   - Works while the contract is paused (audit logs must not be censored).
///   - Two valid signatures for the same positionId both emit (idempotency
///     is the caller's job).
contract VaultPositionClosedTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;
    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal user = address(0xCAFE);

    event PositionClosed(
        bytes32 indexed positionId,
        address indexed user,
        string symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt
    );

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);

        usdc = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (address(usdc), backendSigner, referralStorage, "Primit Vault AVAX Fuji", "1.0.0", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = Vault(address(proxy));
    }

    function _samplePositionId() internal pure returns (bytes32) {
        return bytes32(uint256(0xC10E5ED));
    }

    function _sign(
        uint256 signerKey,
        bytes32 positionId,
        address u,
        string memory symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionClose(bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 fee,uint256 closedAt,uint256 deadline)"
                ),
                positionId,
                u,
                keccak256(bytes(symbol)),
                realizedPnl,
                fee,
                closedAt,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function test_emitsPositionClosed_withValidBackendSignature() public {
        bytes32 pid = _samplePositionId();
        int256 pnl = -1_234_567;
        uint256 fee = 500_000;
        uint256 closedAt = block.timestamp;
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "BTCUSDT", pnl, fee, closedAt, deadline);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(pid, user, "BTCUSDT", pnl, fee, closedAt);

        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", pnl, fee, closedAt, deadline, sig);
    }

    function test_revertsWhen_signatureFromWrongKey() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        // Sign with random non-backend key.
        bytes memory sig = _sign(0xBAD, pid, user, "BTCUSDT", 0, 0, block.timestamp, deadline);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", 0, 0, block.timestamp, deadline, sig);
    }

    function test_revertsWhen_anyFieldTampered() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        // Backend signs with realizedPnl=100, but user tries to submit with realizedPnl=999.
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "BTCUSDT", 100, 1, block.timestamp, deadline);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", 999, 1, block.timestamp, deadline, sig);
    }

    function test_revertsWhen_deadlinePassed() public {
        bytes32 pid = _samplePositionId();
        uint256 closedAt = block.timestamp;
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "BTCUSDT", 0, 0, closedAt, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.SignatureExpired.selector, deadline, deadline + 1)
        );
        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", 0, 0, closedAt, deadline, sig);
    }

    function test_revertsWhen_callerIsNotUser() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "BTCUSDT", 0, 0, block.timestamp, deadline);

        address impostor = address(0xBADBAD);
        vm.expectRevert(abi.encodeWithSelector(Vault.UserMismatch.selector, impostor, user));
        vm.prank(impostor);
        vault.recordPositionClose(pid, user, "BTCUSDT", 0, 0, block.timestamp, deadline, sig);
    }

    function test_revertsWhen_userIsZeroAddress() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, address(0), "BTCUSDT", 0, 0, block.timestamp, deadline);

        vm.expectRevert(Vault.ZeroAddress.selector);
        vm.prank(address(0));
        vault.recordPositionClose(pid, address(0), "BTCUSDT", 0, 0, block.timestamp, deadline, sig);
    }

    function test_revertsWhen_signatureLengthWrong() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        bytes memory badSig = hex"deadbeef"; // 4 bytes, not 65

        vm.expectRevert(
            abi.encodeWithSelector(SignatureVerifier.InvalidSignatureLength.selector, 4)
        );
        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", 0, 0, block.timestamp, deadline, badSig);
    }

    function test_doesNotMutateAnyBalanceOrTotal() public {
        uint256 totalBefore = vault.getTotalBalance();
        uint256 userBalBefore = vault.balances(user);
        uint256 userDepBefore = vault.depositedBalances(user);
        uint256 nonceBefore = vault.withdrawNonces(user);
        uint256 totDepositsBefore = vault.totalDeposits();
        uint256 totWithdrawalsBefore = vault.totalWithdrawals();

        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        int256 pnl = int256(1_000_000);
        uint256 fee = type(uint256).max;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "BTCUSDT", pnl, fee, block.timestamp, deadline);

        vm.prank(user);
        vault.recordPositionClose(pid, user, "BTCUSDT", pnl, fee, block.timestamp, deadline, sig);

        assertEq(vault.getTotalBalance(), totalBefore);
        assertEq(vault.balances(user), userBalBefore);
        assertEq(vault.depositedBalances(user), userDepBefore);
        assertEq(vault.withdrawNonces(user), nonceBefore);
        assertEq(vault.totalDeposits(), totDepositsBefore);
        assertEq(vault.totalWithdrawals(), totWithdrawalsBefore);
    }

    function test_worksWhilePaused() public {
        vm.prank(admin);
        vault.pause();

        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "ETHUSDT", 0, 0, 1, deadline);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(pid, user, "ETHUSDT", 0, 0, 1);
        vm.prank(user);
        vault.recordPositionClose(pid, user, "ETHUSDT", 0, 0, 1, deadline, sig);
    }

    function test_duplicatePositionIdEmitsTwiceWithSameSignature() public {
        bytes32 pid = _samplePositionId();
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = _sign(BACKEND_KEY, pid, user, "SOLUSDT", 100, 1, 1, deadline);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(pid, user, "SOLUSDT", 100, 1, 1);
        vm.prank(user);
        vault.recordPositionClose(pid, user, "SOLUSDT", 100, 1, 1, deadline, sig);

        // Same signature, same caller, same data — still emits (no nonce).
        // Backend is expected to refuse signing a duplicate close, but the
        // contract is a dumb pipe.
        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(pid, user, "SOLUSDT", 100, 1, 1);
        vm.prank(user);
        vault.recordPositionClose(pid, user, "SOLUSDT", 100, 1, 1, deadline, sig);
    }
}
