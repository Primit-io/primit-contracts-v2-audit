// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "../src/contracts/core/vault/Vault.sol";
import "../src/contracts/interfaces/IVault.sol";

contract VaultCloseOperatorPermitTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;

    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    uint256 internal constant USER_KEY = 0xC10E5E;

    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal user;
    address internal operator = address(0x0F_EE);

    event PositionClosed(
        bytes32 indexed positionId,
        address indexed user,
        string symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt
    );

    event PositionCloseOperatorApproved(
        address indexed user, address indexed operator, uint64 expiresAt, uint256 nonce
    );

    event PositionCloseRecorded(
        bytes32 indexed closeId, bytes32 indexed positionId, address indexed user, address operator
    );

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

    event PositionBalanceSettled(
        bytes32 indexed settlementKey,
        address indexed user,
        int256 balanceDelta,
        uint256 creditedAmount,
        uint256 debitedAmount,
        uint256 newBalance,
        uint256 invalidatedNonce
    );

    event ProtocolFeeAccrued(
        bytes32 indexed closeId,
        address indexed user,
        address indexed token,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 borrowingFee,
        uint256 accruedAmount
    );

    struct CloseSigInput {
        bytes32 closeId;
        bytes32 positionId;
        address closeUser;
        string symbol;
        int256 realizedPnl;
        uint256 fee;
        uint256 closedAt;
        uint256 deadline;
    }

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);
        user = vm.addr(USER_KEY);

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
        vm.prank(admin);
        vault.setProtocolFeeRecipient(admin);
    }

    function _signOperatorPermit(
        uint256 signerKey,
        address permitUser,
        address permitOperator,
        uint64 expiresAt,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "CloseOperatorPermit(address user,address operator,uint64 expiresAt,uint256 nonce,uint256 deadline)"
                ),
                permitUser,
                permitOperator,
                expiresAt,
                nonce,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _signPositionClose(uint256 signerKey, CloseSigInput memory input) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionClose(bytes32 closeId,bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 fee,uint256 closedAt,uint256 deadline)"
                ),
                input.closeId,
                input.positionId,
                input.closeUser,
                keccak256(bytes(input.symbol)),
                input.realizedPnl,
                input.fee,
                input.closedAt,
                input.deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _permitOperator(uint64 expiresAt) internal {
        uint256 deadline = block.timestamp + 300;
        uint256 nonce = vault.closeOperatorNonces(user);
        bytes memory signature = _signOperatorPermit(USER_KEY, user, operator, expiresAt, nonce, deadline);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionCloseOperatorApproved(user, operator, expiresAt, nonce);

        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);
    }

    function _deposit(address account, uint256 amount) internal {
        usdc.mint(account, amount);
        vm.startPrank(account);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, bytes32(0));
        vm.stopPrank();
    }

    function _signedClose(bytes32 closeId, bytes32 positionId, int256 pnl, uint256 fee)
        internal
        view
        returns (bytes memory signature, uint256 closedAt, uint256 deadline)
    {
        closedAt = block.timestamp;
        deadline = block.timestamp + 300;
        signature = _signPositionClose(
            BACKEND_KEY,
            CloseSigInput({
                closeId: closeId,
                positionId: positionId,
                closeUser: user,
                symbol: "BTCUSDT",
                realizedPnl: pnl,
                fee: fee,
                closedAt: closedAt,
                deadline: deadline
            })
        );
    }

    function _signedCloseSettlement(
        bytes32 closeId,
        bytes32 positionId,
        int256 pnl,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 borrowingFee,
        int256 balanceDelta
    ) internal view returns (bytes memory signature, uint256 closedAt, uint256 deadline) {
        closedAt = block.timestamp;
        deadline = block.timestamp + 300;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionCloseSettlement(bytes32 closeId,bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 tradingFee,int256 fundingFee,uint256 borrowingFee,int256 balanceDelta,uint256 closedAt,uint256 deadline)"
                ),
                closeId,
                positionId,
                user,
                keccak256(bytes("BTCUSDT")),
                pnl,
                tradingFee,
                fundingFee,
                borrowingFee,
                balanceDelta,
                closedAt,
                deadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BACKEND_KEY, hash);
        signature = abi.encodePacked(r, s, v);
    }

    function test_permitAllowsOperatorToRecordMultipleClosesWithoutUserSender() public {
        uint64 expiresAt = uint64(block.timestamp + 30 days);
        _permitOperator(expiresAt);

        assertEq(vault.closeOperatorApprovalExpiries(user, operator), expiresAt);
        assertEq(vault.closeOperatorNonces(user), 1);

        bytes32 positionIdOne = keccak256("position-one");
        bytes32 closeIdOne = keccak256("close-one");
        (bytes memory sigOne, uint256 closedAtOne, uint256 deadlineOne) =
            _signedClose(closeIdOne, positionIdOne, 125, 7);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(positionIdOne, user, "BTCUSDT", 125, 7, closedAtOne);
        vm.expectEmit(true, true, true, true, address(vault));
        emit PositionCloseRecorded(closeIdOne, positionIdOne, user, operator);
        vm.expectEmit(true, true, true, true, address(vault));
        emit PositionCloseAuditRecorded(closeIdOne, positionIdOne, user, operator, "BTCUSDT", 125, 7, closedAtOne);

        vm.prank(operator);
        vault.recordPositionCloseFor(
            closeIdOne, positionIdOne, user, "BTCUSDT", 125, 7, closedAtOne, deadlineOne, sigOne
        );

        bytes32 positionIdTwo = keccak256("position-two");
        bytes32 closeIdTwo = keccak256("close-two");
        (bytes memory sigTwo, uint256 closedAtTwo, uint256 deadlineTwo) =
            _signedClose(closeIdTwo, positionIdTwo, -50, 3);

        vm.prank(operator);
        vault.recordPositionCloseFor(
            closeIdTwo, positionIdTwo, user, "BTCUSDT", -50, 3, closedAtTwo, deadlineTwo, sigTwo
        );

        assertTrue(vault.usedCloseIds(closeIdOne));
        assertTrue(vault.usedCloseIds(closeIdTwo));
    }

    function test_revertsWhenCloseIdIsReused() public {
        _permitOperator(uint64(block.timestamp + 30 days));

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("close");
        (bytes memory signature, uint256 closedAt, uint256 deadline) = _signedClose(closeId, positionId, 0, 1);

        vm.prank(operator);
        vault.recordPositionCloseFor(closeId, positionId, user, "BTCUSDT", 0, 1, closedAt, deadline, signature);

        vm.expectRevert(abi.encodeWithSelector(Vault.PositionCloseAlreadyRecorded.selector, closeId));
        vm.prank(operator);
        vault.recordPositionCloseFor(closeId, positionId, user, "BTCUSDT", 0, 1, closedAt, deadline, signature);
    }

    function test_operatorCanRecordAndSettleCloseInOneTransaction() public {
        _permitOperator(uint64(block.timestamp + 30 days));
        _deposit(user, 10 ether);

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("close-and-settle");
        int256 balanceDelta = -3 ether;
        (bytes memory signature, uint256 closedAt, uint256 deadline) =
            _signedCloseSettlement(closeId, positionId, -1 ether, 2 ether, 1 ether, 0, balanceDelta);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionClosed(positionId, user, "BTCUSDT", -1 ether, 2 ether, closedAt);
        vm.expectEmit(true, true, true, true, address(vault));
        emit PositionCloseRecorded(closeId, positionId, user, operator);
        vm.expectEmit(true, true, true, true, address(vault));
        emit PositionCloseAuditRecorded(closeId, positionId, user, operator, "BTCUSDT", -1 ether, 2 ether, closedAt);
        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionBalanceSettled(closeId, user, balanceDelta, 0, 3 ether, 7 ether, 1);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ProtocolFeeAccrued(closeId, user, address(usdc), 2 ether, 1 ether, 0, 3 ether);

        vm.prank(operator);
        (uint256 credited, uint256 debited) = vault.recordPositionCloseAndSettleFor(
            IVault.PositionCloseSettlementParams({
                closeId: closeId,
                positionId: positionId,
                user: user,
                symbol: "BTCUSDT",
                realizedPnl: -1 ether,
                tradingFee: 2 ether,
                fundingFee: 1 ether,
                borrowingFee: 0,
                balanceDelta: balanceDelta,
                closedAt: closedAt,
                deadline: deadline,
                signature: signature
            })
        );

        assertEq(credited, 0);
        assertEq(debited, 3 ether);
        assertTrue(vault.usedCloseIds(closeId));
        assertTrue(vault.usedPositionBalanceSettlements(closeId));
        assertEq(vault.withdrawNonces(user), 1);
        assertEq(vault.getBalance(user), 7 ether);
        assertEq(usdc.balanceOf(admin), 3 ether);
        assertEq(usdc.balanceOf(address(vault)), 7 ether);
    }

    function test_recordAndSettleNegativeFundingReducesProtocolFeeTransfer() public {
        _permitOperator(uint64(block.timestamp + 30 days));
        _deposit(user, 10 ether);

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("negative-funding-close");
        int256 balanceDelta = -2 ether;
        (bytes memory signature, uint256 closedAt, uint256 deadline) =
            _signedCloseSettlement(closeId, positionId, -1 ether, 3 ether, -1 ether, 0, balanceDelta);

        vm.expectEmit(true, true, true, true, address(vault));
        emit ProtocolFeeAccrued(closeId, user, address(usdc), 3 ether, -1 ether, 0, 2 ether);

        vm.prank(operator);
        vault.recordPositionCloseAndSettleFor(
            IVault.PositionCloseSettlementParams({
                closeId: closeId,
                positionId: positionId,
                user: user,
                symbol: "BTCUSDT",
                realizedPnl: -1 ether,
                tradingFee: 3 ether,
                fundingFee: -1 ether,
                borrowingFee: 0,
                balanceDelta: balanceDelta,
                closedAt: closedAt,
                deadline: deadline,
                signature: signature
            })
        );

        assertEq(vault.getBalance(user), 8 ether);
        assertEq(usdc.balanceOf(admin), 2 ether);
        assertEq(usdc.balanceOf(address(vault)), 8 ether);
    }

    function test_ownerCanUpdateProtocolFeeRecipientAndCloseTransfersFees() public {
        _permitOperator(uint64(block.timestamp + 30 days));
        _deposit(user, 10 ether);

        address recipient = address(0xFEE);
        vm.prank(admin);
        vault.setProtocolFeeRecipient(recipient);

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("claimable-fee-close");
        (bytes memory signature, uint256 closedAt, uint256 deadline) =
            _signedCloseSettlement(closeId, positionId, -1 ether, 3 ether, 0, 0, -3 ether);

        vm.prank(operator);
        vault.recordPositionCloseAndSettleFor(
            IVault.PositionCloseSettlementParams({
                closeId: closeId,
                positionId: positionId,
                user: user,
                symbol: "BTCUSDT",
                realizedPnl: -1 ether,
                tradingFee: 3 ether,
                fundingFee: 0,
                borrowingFee: 0,
                balanceDelta: -3 ether,
                closedAt: closedAt,
                deadline: deadline,
                signature: signature
            })
        );

        assertEq(usdc.balanceOf(recipient), 3 ether);
        assertEq(usdc.balanceOf(address(vault)), 7 ether);
    }

    function test_recordAndSettleRejectsUnsignedBalanceDelta() public {
        _permitOperator(uint64(block.timestamp + 30 days));

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("close-and-settle");
        (bytes memory signature, uint256 closedAt, uint256 deadline) =
            _signedCloseSettlement(closeId, positionId, 1 ether, 0, 0, 0, 1 ether);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(operator);
        vault.recordPositionCloseAndSettleFor(
            IVault.PositionCloseSettlementParams({
                closeId: closeId,
                positionId: positionId,
                user: user,
                symbol: "BTCUSDT",
                realizedPnl: 1 ether,
                tradingFee: 0,
                fundingFee: 0,
                borrowingFee: 0,
                balanceDelta: 2 ether,
                closedAt: closedAt,
                deadline: deadline,
                signature: signature
            })
        );
    }

    function test_revertsWhenBackendSignatureDoesNotBindCloseId() public {
        _permitOperator(uint64(block.timestamp + 30 days));

        bytes32 signedCloseId = keccak256("signed-close");
        bytes32 submittedCloseId = keccak256("submitted-close");
        bytes32 positionId = keccak256("position");
        (bytes memory signature, uint256 closedAt, uint256 deadline) = _signedClose(signedCloseId, positionId, 42, 1);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(operator);
        vault.recordPositionCloseFor(
            submittedCloseId, positionId, user, "BTCUSDT", 42, 1, closedAt, deadline, signature
        );
    }

    function test_revertsWhenOperatorApprovalExpired() public {
        uint64 expiresAt = uint64(block.timestamp + 10);
        _permitOperator(expiresAt);
        vm.warp(expiresAt + 1);

        bytes32 positionId = keccak256("position");
        bytes32 closeId = keccak256("close");
        (bytes memory signature, uint256 closedAt, uint256 deadline) = _signedClose(closeId, positionId, 0, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Vault.CloseOperatorApprovalExpired.selector, user, operator, expiresAt, block.timestamp
            )
        );
        vm.prank(operator);
        vault.recordPositionCloseFor(closeId, positionId, user, "BTCUSDT", 0, 1, closedAt, deadline, signature);
    }

    function test_revertsWhenPermitSignatureIsReplayed() public {
        uint64 expiresAt = uint64(block.timestamp + 30 days);
        uint256 deadline = block.timestamp + 300;
        bytes memory signature = _signOperatorPermit(USER_KEY, user, operator, expiresAt, 0, deadline);

        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);
    }

    // ================================================================
    // CertiK PRI-13 · permitCloseOperator must reject non-future expiresAt
    // ================================================================

    /// @notice expiresAt = 0 must revert ExpiresAtInPast and NOT consume nonce
    function test_PRI13_permit_rejects_zero_expiresAt() public {
        uint256 nonceBefore = vault.closeOperatorNonces(user);
        uint256 deadline = block.timestamp + 300;
        uint64 expiresAt = 0;
        bytes memory signature = _signOperatorPermit(USER_KEY, user, operator, expiresAt, nonceBefore, deadline);

        vm.expectRevert(abi.encodeWithSelector(Vault.ExpiresAtInPast.selector, expiresAt, block.timestamp));
        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);

        assertEq(vault.closeOperatorNonces(user), nonceBefore, "nonce must not be consumed on rejected permit");
        assertEq(vault.closeOperatorApprovalExpiries(user, operator), 0);
    }

    /// @notice expiresAt in the past must revert ExpiresAtInPast
    function test_PRI13_permit_rejects_past_expiresAt() public {
        // Warp forward so we have room to sign a "past" expiresAt without underflow.
        vm.warp(block.timestamp + 1000);
        uint256 nonceBefore = vault.closeOperatorNonces(user);
        uint256 deadline = block.timestamp + 300;
        uint64 expiresAt = uint64(block.timestamp - 1);
        bytes memory signature = _signOperatorPermit(USER_KEY, user, operator, expiresAt, nonceBefore, deadline);

        vm.expectRevert(abi.encodeWithSelector(Vault.ExpiresAtInPast.selector, expiresAt, block.timestamp));
        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);

        assertEq(vault.closeOperatorNonces(user), nonceBefore, "nonce must not be consumed on rejected permit");
    }

    /// @notice expiresAt == block.timestamp is treated as not-strictly-future and must revert
    function test_PRI13_permit_rejects_expiresAt_equal_to_now() public {
        uint256 nonceBefore = vault.closeOperatorNonces(user);
        uint256 deadline = block.timestamp + 300;
        uint64 expiresAt = uint64(block.timestamp);
        bytes memory signature = _signOperatorPermit(USER_KEY, user, operator, expiresAt, nonceBefore, deadline);

        vm.expectRevert(abi.encodeWithSelector(Vault.ExpiresAtInPast.selector, expiresAt, block.timestamp));
        vm.prank(operator);
        vault.permitCloseOperator(user, operator, expiresAt, deadline, signature);
    }

    /// @notice future expiresAt still succeeds (regression guard for the happy path)
    function test_PRI13_permit_accepts_future_expiresAt() public {
        uint64 expiresAt = uint64(block.timestamp + 30 days);
        _permitOperator(expiresAt);
        assertEq(vault.closeOperatorApprovalExpiries(user, operator), expiresAt);
    }

    // ================================================================
    // CertiK PRI-14 · recordPositionCloseAndSettleFor must not emit a
    //                 stale PositionBalanceSettled event when the closeId
    //                 was already consumed via direct settlePositionBalance.
    // ================================================================

    /// @notice Backend settles via settlePositionBalance(user, delta, closeId) first,
    ///         then an AA operator submits recordPositionCloseAndSettleFor with the
    ///         same closeId. The audit-side events (PositionClosed /
    ///         PositionCloseRecorded / PositionCloseAuditRecorded) must still emit,
    ///         but the stale PositionBalanceSettled event and the protocol-fee
    ///         transfer must be skipped. Return must be (0, 0) and balance / nonce
    ///         must be unchanged relative to the direct-settle snapshot.
    function test_PRI14_no_stale_PositionBalanceSettled_event_on_replay() public {
        _permitOperator(uint64(block.timestamp + 30 days));
        _deposit(user, 10 ether);

        // Raise settlement caps so the direct-settle path is not blocked (cap defaults to 0).
        vm.startPrank(admin);
        vault.setDailySettlementCreditCap(100 ether);
        vault.setDailyUserSettlementCreditCap(100 ether);
        vm.stopPrank();

        bytes32 positionId = keccak256("PRI14-pos");
        bytes32 closeId = keccak256("PRI14-dup");
        int256 balanceDelta = -3 ether;

        // Step 1: backend consumes usedPositionBalanceSettlements[closeId] via the direct path.
        vm.prank(backendSigner);
        vault.settlePositionBalance(user, balanceDelta, closeId);
        assertTrue(vault.usedPositionBalanceSettlements(closeId));
        uint256 balanceAfterDirect = vault.getBalance(user);
        uint256 nonceAfterDirect = vault.withdrawNonces(user);
        uint256 vaultUsdcAfterDirect = usdc.balanceOf(address(vault));

        // Step 2: AA operator submits recordPositionCloseAndSettleFor with the SAME closeId.
        (bytes memory signature, uint256 closedAt, uint256 deadline) =
            _signedCloseSettlement(closeId, positionId, -1 ether, 2 ether, 1 ether, 0, balanceDelta);

        vm.recordLogs();
        vm.prank(operator);
        (uint256 credited, uint256 debited) = vault.recordPositionCloseAndSettleFor(
            IVault.PositionCloseSettlementParams({
                closeId: closeId,
                positionId: positionId,
                user: user,
                symbol: "BTCUSDT",
                realizedPnl: -1 ether,
                tradingFee: 2 ether,
                fundingFee: 1 ether,
                borrowingFee: 0,
                balanceDelta: balanceDelta,
                closedAt: closedAt,
                deadline: deadline,
                signature: signature
            })
        );

        // Return values are zero and no state moved.
        assertEq(credited, 0);
        assertEq(debited, 0);
        assertEq(vault.getBalance(user), balanceAfterDirect, "balance drifted");
        assertEq(vault.withdrawNonces(user), nonceAfterDirect, "nonce drifted");
        assertEq(usdc.balanceOf(address(vault)), vaultUsdcAfterDirect, "vault USDC drifted (fee double-charged?)");

        // Assert log shape: PositionBalanceSettled MUST NOT appear in this tx.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 settledSig = keccak256("PositionBalanceSettled(bytes32,address,int256,uint256,uint256,uint256,uint256)");
        bytes32 closedSig = keccak256("PositionClosed(bytes32,address,string,int256,uint256,uint256)");
        bool sawStaleSettled = false;
        bool sawClosed = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == settledSig) sawStaleSettled = true;
            if (logs[i].topics[0] == closedSig) sawClosed = true;
        }
        assertFalse(sawStaleSettled, "PRI-14: stale PositionBalanceSettled emitted on replay branch");
        assertTrue(sawClosed, "close audit events must still emit for indexer completeness");
    }
}
