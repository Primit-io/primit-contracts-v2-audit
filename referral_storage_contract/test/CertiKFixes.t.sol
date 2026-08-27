// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/referral/ReferralStorage.sol";

/// @notice CertiK Preliminary findings fixes · ReferralStorage side
/// @dev  Covers PRI-08 (setReferrerTier requires tier initialized first)
contract CertiKFixesReferralTest is Test {
    ReferralStorage internal rs;
    address internal admin = address(0xA0A0);
    address internal referrer = address(0xBEEF);

    function setUp() public {
        ReferralStorage impl = new ReferralStorage();
        bytes memory initData = abi.encodeCall(ReferralStorage.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        rs = ReferralStorage(address(proxy));
    }

    // ================================================================
    // PRI-08 · setReferrerTier rejects non-initialized tierId
    // ================================================================
    function test_PRI08_setReferrerTier_rejects_uninitialized_tier() public {
        uint256 uninitTier = 42;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ReferralStorage.TierNotInitialized.selector, uninitTier));
        rs.setReferrerTier(referrer, uninitTier);
    }

    function test_PRI08_setReferrerTier_accepts_after_setTier() public {
        uint256 tid = 3;
        vm.startPrank(admin);
        rs.setTier(tid, 2000, 5000); // init tier 3
        rs.setReferrerTier(referrer, tid);
        vm.stopPrank();
        assertEq(rs.referrerTiers(referrer), tid);
    }

    function test_PRI08_setReferrerTier_accepts_tier_zero_as_default() public {
        // tier 0 is intentionally allowed (interpreted as "no tier / default zero rebate")
        vm.prank(admin);
        rs.setReferrerTier(referrer, 0);
        assertEq(rs.referrerTiers(referrer), 0);
    }

    // ================================================================
    // PRI-17 · grantHandlerRole / revokeHandlerRole work for an
    //          ADMIN_ROLE-only caller (no implicit DEFAULT_ADMIN_ROLE)
    // ================================================================

    /// @notice A separate account that holds ONLY ADMIN_ROLE (not DEFAULT_ADMIN_ROLE)
    ///         must be able to grant HANDLER_ROLE through the wrapper. Pre-fix, the
    ///         wrapper called OZ's public `grantRole` which enforced
    ///         DEFAULT_ADMIN_ROLE and reverted here.
    function test_PRI17_grantHandlerRole_works_for_admin_role_only_caller() public {
        address adminOnly = address(0xADEA);
        address handler = address(0xC0DE);
        bytes32 adminRoleHash = rs.ADMIN_ROLE();
        bytes32 handlerRoleHash = rs.HANDLER_ROLE();

        // Bootstrap: current admin (which holds both DEFAULT_ADMIN_ROLE + ADMIN_ROLE
        // from initialize) grants ADMIN_ROLE to `adminOnly` — but NOT DEFAULT_ADMIN_ROLE.
        vm.prank(admin);
        rs.grantRole(adminRoleHash, adminOnly);
        assertTrue(rs.hasRole(adminRoleHash, adminOnly));
        assertFalse(rs.hasRole(0x00, adminOnly), "adminOnly must not hold DEFAULT_ADMIN_ROLE");

        // Post-fix: adminOnly can grant HANDLER_ROLE via the wrapper.
        vm.prank(adminOnly);
        rs.grantHandlerRole(handler);
        assertTrue(rs.hasRole(handlerRoleHash, handler));
    }

    /// @notice Symmetric: ADMIN_ROLE-only caller can revoke via the wrapper.
    function test_PRI17_revokeHandlerRole_works_for_admin_role_only_caller() public {
        address adminOnly = address(0xADEA);
        address handler = address(0xC0DE);

        vm.startPrank(admin);
        rs.grantRole(rs.ADMIN_ROLE(), adminOnly);
        rs.grantHandlerRole(handler);
        vm.stopPrank();
        assertTrue(rs.hasRole(rs.HANDLER_ROLE(), handler));

        vm.prank(adminOnly);
        rs.revokeHandlerRole(handler);
        assertFalse(rs.hasRole(rs.HANDLER_ROLE(), handler));
    }

    /// @notice grantHandlerRole still rejects a non-ADMIN caller (regression guard).
    function test_PRI17_grantHandlerRole_rejects_non_admin() public {
        address stranger = address(0xBAD);
        vm.expectRevert(); // OZ AccessControlUnauthorizedAccount
        vm.prank(stranger);
        rs.grantHandlerRole(address(0xC0DE));
    }

    /// @notice grantHandlerRole still rejects zero-address handler.
    function test_PRI17_grantHandlerRole_rejects_zero_handler() public {
        vm.prank(admin);
        vm.expectRevert(ReferralStorage.ZeroAddress.selector);
        rs.grantHandlerRole(address(0));
    }
}
