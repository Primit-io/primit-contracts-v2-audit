// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @notice CertiK Preliminary findings fixes · Vault side
/// @dev  Covers PRI-09 (setReferralStorage + reinitializeEip712DomainVersion emits) · PRI-11 (zero-address check)
contract CertiKFixesVaultTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;
    address internal admin = address(0xA0A0);
    address internal backendSigner = address(0xBEEF);
    address internal referral = address(0xCAFE);

    event ReferralStorageUpdated(address indexed oldReferralStorage, address indexed newReferralStorage);
    event Eip712DomainVersionUpdated(string oldVersion, string newVersion);

    function setUp() public {
        vm.chainId(43_114);
        usdc = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (address(usdc), backendSigner, referral, "Primit Vault AVAX", "1.0.0", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = Vault(address(proxy));
    }

    // ================================================================
    // PRI-11 · Vault.setReferralStorage rejects zero address
    // ================================================================
    function test_PRI11_setReferralStorage_rejects_zero_address() public {
        vm.prank(admin);
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.setReferralStorage(address(0));
    }

    // ================================================================
    // PRI-09 · Vault.setReferralStorage emits ReferralStorageUpdated
    // ================================================================
    function test_PRI09_setReferralStorage_emits() public {
        address newRs = address(0xC0FE);
        vm.expectEmit(true, true, false, false);
        emit ReferralStorageUpdated(referral, newRs);
        vm.prank(admin);
        vault.setReferralStorage(newRs);
    }

    // ================================================================
    // PRI-09 · Vault.reinitializeEip712DomainVersion emits Eip712DomainVersionUpdated
    // ================================================================
    function test_PRI09_reinitializeEip712DomainVersion_emits() public {
        // Upgrade to fresh impl so reinitializer(2) works on the SAME proxy
        Vault newImpl = new Vault();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        vm.expectEmit(false, false, false, true);
        emit Eip712DomainVersionUpdated("1.0.0", "1.0.1");
        vm.prank(admin);
        vault.reinitializeEip712DomainVersion("1.0.1");
        assertEq(vault.VERSION(), "1.0.1");
    }

    // ================================================================
    // PRI-06 · Vault.reinitializeSettlementCaps must be onlyOwner
    // ================================================================

    /// @notice non-owner direct call must revert with OwnableUnauthorizedAccount
    function test_PRI06_reinitializeSettlementCaps_rejects_non_owner() public {
        address stranger = address(0xBAD5);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger)
        );
        vm.prank(stranger);
        vault.reinitializeSettlementCaps(100 ether, 10 ether);
    }

    /// @notice owner direct call succeeds and atomically sets both caps
    function test_PRI06_reinitializeSettlementCaps_owner_sets_caps() public {
        vm.prank(admin);
        vault.reinitializeSettlementCaps(100 ether, 10 ether);
        assertEq(vault.dailySettlementCreditCap(), 100 ether);
        assertEq(vault.dailyUserSettlementCreditCap(), 10 ether);
    }

    // ================================================================
    // PRI-11 · setPlpVaultAddress · owner-gated rotate-friendly setter
    // ================================================================

    event PLPAddressUpdated(address indexed oldPlp, address indexed newPlp);

    /// @notice non-owner call reverts OwnableUnauthorizedAccount
    function test_PRI11_setPlpVaultAddress_rejects_non_owner() public {
        address stranger = address(0xBAD5);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger)
        );
        vm.prank(stranger);
        vault.setPlpVaultAddress(address(0xC0DE));
    }

    /// @notice owner cannot set zero-address
    function test_PRI11_setPlpVaultAddress_rejects_zero_address() public {
        vm.prank(admin);
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.setPlpVaultAddress(address(0));
    }

    /// @notice owner set succeeds · plpVaultAddress updated · PLPAddressUpdated event emitted
    function test_PRI11_setPlpVaultAddress_owner_updates_and_emits() public {
        address newPlp = address(0xC0DE);
        address oldPlp = vault.plpVaultAddress();

        vm.expectEmit(true, true, false, false, address(vault));
        emit PLPAddressUpdated(oldPlp, newPlp);

        vm.prank(admin);
        vault.setPlpVaultAddress(newPlp);
        assertEq(vault.plpVaultAddress(), newPlp);
    }

    /// @notice owner can rotate the PLP address multiple times
    function test_PRI11_setPlpVaultAddress_owner_can_rotate() public {
        vm.prank(admin);
        vault.setPlpVaultAddress(address(0xC0DE));
        vm.prank(admin);
        vault.setPlpVaultAddress(address(0xFEED));
        assertEq(vault.plpVaultAddress(), address(0xFEED));
    }

    // ================================================================
    // PRI-26 · setMaxProtocolFeeAmount owner-gated + cap enforcement
    // ================================================================

    event MaxProtocolFeeAmountUpdated(uint256 oldMax, uint256 newMax);

    /// @notice Freshly-deployed proxy starts with cap disabled (0) for backward compat.
    function test_PRI26_maxProtocolFeeAmount_starts_disabled() public view {
        assertEq(vault.maxProtocolFeeAmount(), 0);
    }

    /// @notice Owner setter updates + emits event.
    function test_PRI26_setMaxProtocolFeeAmount_owner_updates_and_emits() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit MaxProtocolFeeAmountUpdated(0, 1_000_000e6);
        vm.prank(admin);
        vault.setMaxProtocolFeeAmount(1_000_000e6);
        assertEq(vault.maxProtocolFeeAmount(), 1_000_000e6);
    }

    /// @notice Setter rejects zero so the cap cannot be disabled after enabling.
    function test_PRI26_setMaxProtocolFeeAmount_rejects_zero() public {
        vm.expectRevert(Vault.ZeroMaxProtocolFeeAmount.selector);
        vm.prank(admin);
        vault.setMaxProtocolFeeAmount(0);
    }

    /// @notice Non-owner setter rejected.
    function test_PRI26_setMaxProtocolFeeAmount_rejects_non_owner() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        vault.setMaxProtocolFeeAmount(1_000_000e6);
    }
}
