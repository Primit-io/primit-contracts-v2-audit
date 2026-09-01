// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../src/contracts/core/liquidation/LiquidationManager.sol";
import "../src/contracts/core/vault/Vault.sol";

contract LiquidationManagerTest is Test {
    using MessageHashUtils for bytes32;

    Vault internal vault;
    LiquidationManager internal manager;
    ERC20Mock internal usdc;

    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    uint256 internal constant ORACLE_KEY = 0xA11CE0;
    address internal backendSigner;
    address internal oracleSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal user = address(0xCAFE);
    address internal keeper = address(0xA55E7);
    address internal settlementRecipient = address(0xFEE);

    bytes32 internal constant BTC = keccak256("BTCUSDT");
    bytes32 internal constant POSITION_ID = keccak256("position-1");

    event LiquidationExecuted(
        bytes32 indexed positionId,
        bytes32 indexed liquidationKey,
        address indexed user,
        bytes32 symbol,
        uint256 markPrice,
        int256 remainingCollateral,
        uint256 maintenanceMargin,
        uint256 debitedAmount,
        address keeper
    );

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);
        oracleSigner = vm.addr(ORACLE_KEY);

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

        manager = new LiquidationManager(address(vault), backendSigner, oracleSigner, settlementRecipient, admin);

        vm.startPrank(admin);
        vault.setLiquidationManager(address(manager));
        manager.setKeeper(keeper, true);
        vm.stopPrank();

        usdc.mint(user, 1_000 ether);
        vm.startPrank(user);
        usdc.approve(address(vault), 1_000 ether);
        vault.deposit(1_000 ether, bytes32(0));
        vm.stopPrank();
    }

    function _snapshot(uint64 nonce) internal view returns (LiquidationManager.PositionSnapshot memory) {
        return LiquidationManager.PositionSnapshot({
            user: user,
            symbol: BTC,
            side: LiquidationManager.PositionSide.Long,
            sizeUsd: 1_000 ether,
            sizeTokens: 10 ether,
            collateral: 100 ether,
            accumulatedFunding: 0,
            accumulatedBorrowing: 0,
            maintenanceMarginRate: 5e16,
            liquidationFeeRate: 5e15,
            nonce: nonce,
            updatedAt: uint64(block.timestamp),
            status: LiquidationManager.SnapshotStatus.Open
        });
    }

    function _signSnapshot(LiquidationManager.PositionSnapshot memory snap) internal view returns (bytes memory) {
        bytes32 digest = manager.snapshotHash(POSITION_ID, snap).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BACKEND_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _oraclePrice(uint256 price, uint256 signingKey)
        internal
        view
        returns (LiquidationManager.OraclePrice memory)
    {
        uint64 updatedAt = uint64(block.timestamp);
        uint64 maxStaleness = 30;
        LiquidationManager.OraclePrice memory oracle = LiquidationManager.OraclePrice({
            symbol: BTC, price: price, updatedAt: updatedAt, maxStaleness: maxStaleness, signature: ""
        });
        bytes32 digest = manager.oracleHash(oracle).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        oracle.signature = abi.encodePacked(r, s, v);
        return oracle;
    }

    function test_liquidateWithOraclePriceDebitsVaultBalance() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(94 ether, ORACLE_KEY);
        bytes32 liquidationKey = keccak256(abi.encodePacked(POSITION_ID, snap.nonce, oracle.price, oracle.updatedAt));

        vm.expectEmit(true, true, true, true, address(manager));
        emit LiquidationExecuted(POSITION_ID, liquidationKey, user, BTC, 94 ether, 40 ether, 50 ether, 5 ether, keeper);

        vm.prank(keeper);
        (bytes32 returnedKey, uint256 debitedAmount) = manager.liquidate(POSITION_ID, oracle);

        assertEq(returnedKey, liquidationKey);
        assertEq(debitedAmount, 5 ether);
        assertEq(vault.balances(user), 995 ether);
        assertEq(usdc.balanceOf(settlementRecipient), 5 ether);
        assertEq(uint8(manager.snapshotStatus(POSITION_ID)), uint8(LiquidationManager.SnapshotStatus.Liquidated));
        assertTrue(vault.usedLiquidationSettlements(liquidationKey));
    }

    function test_revertsWhenOraclePriceDoesNotMakePositionLiquidatable() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(96 ether, ORACLE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(LiquidationManager.NotLiquidatable.selector, int256(60 ether), int256(50 ether))
        );
        vm.prank(keeper);
        manager.liquidate(POSITION_ID, oracle);
    }

    function test_revertsWhenOracleSignatureIsNotTrusted() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(94 ether, 0xBAD);

        vm.expectRevert(LiquidationManager.InvalidSignature.selector);
        vm.prank(keeper);
        manager.liquidate(POSITION_ID, oracle);
    }

    function test_revertsWhenCallerIsNotKeeper() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(94 ether, ORACLE_KEY);

        vm.expectRevert(abi.encodeWithSelector(LiquidationManager.UnauthorizedKeeper.selector, address(this)));
        manager.liquidate(POSITION_ID, oracle);
    }

    function test_revertsWhenSnapshotNonceIsStale() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(2);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));
        assertEq(manager.snapshotNonce(POSITION_ID), 2);

        LiquidationManager.PositionSnapshot memory stale = _snapshot(1);
        bytes memory staleSignature = _signSnapshot(stale);
        vm.expectRevert(abi.encodeWithSelector(LiquidationManager.StaleNonce.selector, uint64(1), uint64(2)));
        manager.updateSnapshot(POSITION_ID, stale, staleSignature);
    }

    function test_snapshotCanReferenceUserWithZeroVaultBalance() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        snap.user = address(0xB0B);
        snap.collateral = 101 ether;
        bytes memory signature = _signSnapshot(snap);

        manager.updateSnapshot(POSITION_ID, snap, signature);

        assertEq(manager.snapshotNonce(POSITION_ID), 1);
    }

    // ================================================================
    // CertiK PRI-07 · Negative `remaining` must NOT sweep the user's
    // entire shared Vault balance. Cap to (fee + shortfall).
    // ================================================================

    event LiquidationBadDebt(
        bytes32 indexed positionId,
        bytes32 indexed liquidationKey,
        address indexed user,
        uint256 obligation,
        uint256 debitedAmount,
        uint256 badDebt
    );

    /// @notice Snapshot params yield sizeUsd=1000, collateral=100, fee=5.
    ///         At price=89 ETH: pnl = 10*89 - 1000 = -110; remaining = -10;
    ///         shortfall = 10; obligation = fee + shortfall = 15.
    ///         User has 1000 ether in Vault balance, so debit MUST be 15 and
    ///         leftover balance MUST be 985 (unrelated funds preserved).
    function test_PRI07_liquidate_debits_only_obligation_when_shortfall_and_balance_sufficient() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);

        uint256 balanceBefore = vault.balances(user);
        assertEq(balanceBefore, 1_000 ether);

        vm.prank(keeper);
        (, uint256 debitedAmount) = manager.liquidate(POSITION_ID, oracle);

        // obligation = fee(5) + shortfall(10) = 15. Balance sufficient => full obligation debited.
        assertEq(debitedAmount, 15 ether, "must debit exactly obligation, not full balance");
        assertEq(vault.balances(user), balanceBefore - 15 ether, "unrelated funds must be preserved");
        assertEq(usdc.balanceOf(settlementRecipient), 15 ether);
    }

    /// @notice Same snapshot, but user's Vault balance has been drawn down to 10
    ///         via a backend settlement. obligation=15 > balance=10.
    ///         Expected: debit=10, badDebt=5, LiquidationBadDebt event emitted,
    ///         and balance goes to 0 (no negative balance).
    function test_PRI07_liquidate_emits_bad_debt_when_obligation_exceeds_balance() public {
        // Drain user balance from 1000 to 10 via backend-signed settlement
        vm.prank(backendSigner);
        vault.settlePositionBalance(user, -990 ether, keccak256("PRI07-drain"));
        assertEq(vault.balances(user), 10 ether);

        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);
        bytes32 liquidationKey = keccak256(abi.encodePacked(POSITION_ID, snap.nonce, oracle.price, oracle.updatedAt));

        // Expect BadDebt event: obligation=15, debited=10, badDebt=5
        vm.expectEmit(true, true, true, true, address(manager));
        emit LiquidationBadDebt(POSITION_ID, liquidationKey, user, 15 ether, 10 ether, 5 ether);

        vm.prank(keeper);
        (, uint256 debitedAmount) = manager.liquidate(POSITION_ID, oracle);

        assertEq(debitedAmount, 10 ether, "debit capped at balance");
        assertEq(vault.balances(user), 0, "balance drained but not negative");
        assertEq(usdc.balanceOf(settlementRecipient), 10 ether);
    }

    /// @notice Regression guard: pre-fix, remaining<0 would set clearBalance=true
    ///         and sweep the entire 1000 ether. Post-fix, only 15 is taken.
    ///         If this assertion ever reads 1000 again, PRI-07 has regressed.
    function test_PRI07_no_full_sweep_regression_guard() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);

        vm.prank(keeper);
        manager.liquidate(POSITION_ID, oracle);

        assertTrue(vault.balances(user) > 900 ether, "PRI-07 regression: shared balance was swept");
        assertLt(usdc.balanceOf(settlementRecipient), 20 ether, "PRI-07 regression: recipient received sweep");
    }

    // ================================================================
    // CertiK PRI-16 · Stale PositionSnapshot must not be used to liquidate
    //                 with a fresh oracle price.
    // ================================================================

    event MaxSnapshotAgeUpdated(uint256 oldAge, uint256 newAge);

    /// @notice Default maxSnapshotAge is 300s and readable via the public getter.
    function test_PRI16_maxSnapshotAge_defaults_to_300s() public view {
        assertEq(manager.maxSnapshotAge(), 300);
    }

    /// @notice Snapshot older than maxSnapshotAge combined with a fresh oracle must revert
    ///         StaleSnapshot; the pre-fix behaviour would have proceeded and produced a
    ///         distorted _remainingCollateral verdict.
    function test_PRI16_liquidate_reverts_when_snapshot_stale() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        // Fast-forward past maxSnapshotAge (300s) so the snapshot is stale.
        uint64 stampAtSign = uint64(block.timestamp);
        vm.warp(block.timestamp + 301);

        // Fresh oracle price signed AT the current (advanced) block time.
        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationManager.StaleSnapshot.selector,
                stampAtSign,
                uint256(300),
                block.timestamp
            )
        );
        vm.prank(keeper);
        manager.liquidate(POSITION_ID, oracle);
    }

    /// @notice Snapshot exactly maxSnapshotAge old is still accepted (strict `>` boundary).
    function test_PRI16_liquidate_accepts_snapshot_exactly_at_boundary() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        // Snap.updatedAt == block.timestamp at sign time; warp EXACTLY maxSnapshotAge forward.
        vm.warp(block.timestamp + 300);
        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);

        vm.prank(keeper);
        (, uint256 debitedAmount) = manager.liquidate(POSITION_ID, oracle);
        assertGt(debitedAmount, 0);
    }

    /// @notice Owner can tune maxSnapshotAge; event emitted with old + new.
    function test_PRI16_setMaxSnapshotAge_owner_updates_and_emits() public {
        vm.expectEmit(false, false, false, true, address(manager));
        emit MaxSnapshotAgeUpdated(300, 60);
        vm.prank(admin);
        manager.setMaxSnapshotAge(60);
        assertEq(manager.maxSnapshotAge(), 60);
    }

    /// @notice setMaxSnapshotAge(0) reverts ZeroMaxSnapshotAge to prevent disabling protection.
    function test_PRI16_setMaxSnapshotAge_rejects_zero() public {
        vm.expectRevert(LiquidationManager.ZeroMaxSnapshotAge.selector);
        vm.prank(admin);
        manager.setMaxSnapshotAge(0);
    }

    /// @notice Non-owner cannot change maxSnapshotAge.
    function test_PRI16_setMaxSnapshotAge_rejects_non_owner() public {
        vm.expectRevert(); // Ownable
        vm.prank(address(0xBAD));
        manager.setMaxSnapshotAge(60);
    }

    // ================================================================
    // CertiK PRI-26 · on-chain bounds on liquidationFeeRate / maintenanceMarginRate
    // ================================================================

    event MaxLiquidationFeeRateUpdated(uint256 oldMax, uint256 newMax);
    event MaintenanceMarginRateBoundsUpdated(uint256 oldMin, uint256 oldMax, uint256 newMin, uint256 newMax);

    function test_PRI26_defaults_are_conservative() public view {
        assertEq(manager.maxLiquidationFeeRate(), 5e16);
        assertEq(manager.minMaintenanceMarginRate(), 1e15);
        assertEq(manager.maxMaintenanceMarginRate(), 5e17);
    }

    /// @notice snap.liquidationFeeRate above the cap is rejected at updateSnapshot time.
    function test_PRI26_updateSnapshot_rejects_liquidationFeeRate_above_max() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        snap.liquidationFeeRate = 6e16; // 6% > 5% default cap
        bytes memory sig = _signSnapshot(snap);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationManager.LiquidationFeeRateOutOfBounds.selector,
                uint256(6e16),
                uint256(5e16)
            )
        );
        manager.updateSnapshot(POSITION_ID, snap, sig);
    }

    /// @notice snap.maintenanceMarginRate below min is rejected.
    function test_PRI26_updateSnapshot_rejects_maintenanceMarginRate_below_min() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        snap.maintenanceMarginRate = 1e14; // 0.01% < 0.1% default min
        bytes memory sig = _signSnapshot(snap);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationManager.MaintenanceMarginRateOutOfBounds.selector,
                uint256(1e14),
                uint256(1e15),
                uint256(5e17)
            )
        );
        manager.updateSnapshot(POSITION_ID, snap, sig);
    }

    /// @notice snap.maintenanceMarginRate above max is rejected.
    function test_PRI26_updateSnapshot_rejects_maintenanceMarginRate_above_max() public {
        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        snap.maintenanceMarginRate = 6e17; // 60% > 50% default max
        bytes memory sig = _signSnapshot(snap);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationManager.MaintenanceMarginRateOutOfBounds.selector,
                uint256(6e17),
                uint256(1e15),
                uint256(5e17)
            )
        );
        manager.updateSnapshot(POSITION_ID, snap, sig);
    }

    /// @notice Owner can retune bounds; new values immediately gate updateSnapshot.
    function test_PRI26_setMaxLiquidationFeeRate_owner_can_tighten() public {
        vm.expectEmit(false, false, false, true, address(manager));
        emit MaxLiquidationFeeRateUpdated(5e16, 1e16);
        vm.prank(admin);
        manager.setMaxLiquidationFeeRate(1e16); // 1% tightened cap
        assertEq(manager.maxLiquidationFeeRate(), 1e16);

        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        // default snap.liquidationFeeRate = 5e15 (0.5%), still under 1% cap; accepted.
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));
        assertEq(manager.snapshotNonce(POSITION_ID), 1);
    }

    /// @notice setter rejects zero (would disable the fee cap).
    function test_PRI26_setMaxLiquidationFeeRate_rejects_zero() public {
        vm.expectRevert(LiquidationManager.InvalidRateBounds.selector);
        vm.prank(admin);
        manager.setMaxLiquidationFeeRate(0);
    }

    /// @notice Bounds setter emits + updates atomically.
    function test_PRI26_setMaintenanceMarginRateBounds_owner_updates_both() public {
        vm.expectEmit(false, false, false, true, address(manager));
        emit MaintenanceMarginRateBoundsUpdated(1e15, 5e17, 2e15, 3e17);
        vm.prank(admin);
        manager.setMaintenanceMarginRateBounds(2e15, 3e17);
        assertEq(manager.minMaintenanceMarginRate(), 2e15);
        assertEq(manager.maxMaintenanceMarginRate(), 3e17);
    }

    /// @notice Bounds setter rejects inverted or zero inputs.
    function test_PRI26_setMaintenanceMarginRateBounds_rejects_invalid() public {
        vm.expectRevert(LiquidationManager.InvalidRateBounds.selector);
        vm.prank(admin);
        manager.setMaintenanceMarginRateBounds(0, 5e17);

        vm.expectRevert(LiquidationManager.InvalidRateBounds.selector);
        vm.prank(admin);
        manager.setMaintenanceMarginRateBounds(1e15, 0);

        vm.expectRevert(LiquidationManager.InvalidRateBounds.selector);
        vm.prank(admin);
        manager.setMaintenanceMarginRateBounds(5e17, 1e15); // min > max
    }

    /// @notice Non-owner rejected on both setters.
    function test_PRI26_bounds_setters_reject_non_owner() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        manager.setMaxLiquidationFeeRate(1e16);

        vm.expectRevert();
        vm.prank(address(0xBAD));
        manager.setMaintenanceMarginRateBounds(1e15, 5e17);
    }

    /// @notice A tightened maxSnapshotAge shortens the window; regression against the setter path.
    function test_PRI16_liquidate_respects_tightened_maxSnapshotAge() public {
        // Tighten first to 30s.
        vm.prank(admin);
        manager.setMaxSnapshotAge(30);

        LiquidationManager.PositionSnapshot memory snap = _snapshot(1);
        manager.updateSnapshot(POSITION_ID, snap, _signSnapshot(snap));

        // Warp 31s — above the new tight window.
        uint64 stampAtSign = uint64(block.timestamp);
        vm.warp(block.timestamp + 31);
        LiquidationManager.OraclePrice memory oracle = _oraclePrice(89 ether, ORACLE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidationManager.StaleSnapshot.selector,
                stampAtSign,
                uint256(30),
                block.timestamp
            )
        );
        vm.prank(keeper);
        manager.liquidate(POSITION_ID, oracle);
    }
}
