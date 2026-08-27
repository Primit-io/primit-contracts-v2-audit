// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "../src/contracts/core/referral/RebateDistributor.sol";
import "../src/contracts/referral/IReferralStorage.sol";

/// @notice CertiK Preliminary findings fixes · Rebate side
/// @dev  Covers PRI-07 (batchSyncRebates duplicate guard) · PRI-09 (missing emits) · PRI-11 (zero-address check)
contract CertiKFixesRebateTest is Test {
    RebateDistributor internal rebate;
    ERC20Mock internal usdc;
    address internal admin = address(0xA0A0);
    address internal backendSigner = address(0xBEEF);
    address internal referral = address(0xCAFE);
    address internal vaultMock = address(0xDD00);

    // event copies (must match interface signatures)
    event ReferralStorageUpdated(address indexed oldReferralStorage, address indexed newReferralStorage);
    event Eip712DomainVersionUpdated(string oldVersion, string newVersion);

    function setUp() public {
        usdc = new ERC20Mock();
        RebateDistributor impl = new RebateDistributor();
        bytes memory initData = abi.encodeCall(
            RebateDistributor.initialize,
            (address(usdc), vaultMock, backendSigner, referral, "Primit Rebate AVAX", "1.0.0", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        rebate = RebateDistributor(address(proxy));
        // fund the contract so transfers succeed
        usdc.mint(address(rebate), 1_000_000 ether);
    }

    // ================================================================
    // PRI-07 · batchSyncRebates rejects duplicate recipients
    // ================================================================
    function test_PRI07_batchSyncRebates_rejects_duplicate() public {
        address[] memory users = new address[](2);
        users[0] = address(0x1111);
        users[1] = address(0x1111); // duplicate
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(RebateDistributor.DuplicateOrUnsortedRecipient.selector, 1, users[1], users[0])
        );
        rebate.batchSyncRebates(users, amounts, 1);
    }

    function test_PRI07_batchSyncRebates_rejects_unsorted() public {
        address[] memory users = new address[](2);
        users[0] = address(0x2222);
        users[1] = address(0x1111); // descending → violates strict ascending
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;

        vm.prank(admin);
        vm.expectRevert();
        rebate.batchSyncRebates(users, amounts, 1);
    }

    function test_PRI07_batchSyncRebates_accepts_sorted_unique() public {
        address[] memory users = new address[](3);
        users[0] = address(0x1111);
        users[1] = address(0x2222);
        users[2] = address(0x3333);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        vm.prank(admin);
        rebate.batchSyncRebates(users, amounts, 1);
        assertEq(rebate.claimedRebates(users[0]), 100);
        assertEq(rebate.claimedRebates(users[1]), 200);
        assertEq(rebate.claimedRebates(users[2]), 300);
    }

    // ================================================================
    // PRI-11 · setReferralStorage rejects zero address
    // ================================================================
    function test_PRI11_setReferralStorage_rejects_zero_address() public {
        vm.prank(admin);
        vm.expectRevert(RebateDistributor.ZeroAddress.selector);
        rebate.setReferralStorage(address(0));
    }

    // ================================================================
    // PRI-09 · setReferralStorage emits ReferralStorageUpdated
    // ================================================================
    function test_PRI09_setReferralStorage_emits() public {
        address newRs = address(0xC0FE);
        vm.expectEmit(true, true, false, false);
        emit ReferralStorageUpdated(referral, newRs);
        vm.prank(admin);
        rebate.setReferralStorage(newRs);
    }
}
