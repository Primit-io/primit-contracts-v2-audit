// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "../src/contracts/core/vault/Vault.sol";

/// @notice Vault.fundVault TDD suite · Phase 6 Track C
/// @dev    fundVault lets the owner (Primit ops) push USDC into the Vault as
///         generic backing without crediting any user's _balances. This backing
///         is what will let PLP.settleUserPnl credit a user's profit without
///         creating an unbacked IOU. Design doc:
///         internal-docs/DESIGN-2026-0916-001-Phase6-Chain-Settlement-Rollout.md
contract VaultFundVaultTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;

    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal user = address(0xC0FFEE);
    address internal stranger = address(0xBADD1E);

    event VaultFunded(address indexed funder, uint256 amount, uint256 newTotalFunded);

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

        usdc.mint(admin, 10_000e6);
        vm.prank(admin);
        usdc.approve(address(vault), type(uint256).max);

        // ERC20Mock reports 18 decimals so initialize sets minDeposit = 10**18.
        // Real USDC is 6 decimals; drop the mock's minimum to 0 so headroom
        // test can exercise deposit with an amount that reads as USDC-scale.
        vm.prank(admin);
        vault.setMinDeposit(0);
    }

    function test_totalFunded_starts_at_zero() public {
        assertEq(vault.totalFunded(), 0);
    }

    function test_fundVault_transfers_usdc_from_caller_to_vault() public {
        uint256 amount = 500e6;
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        uint256 adminBefore = usdc.balanceOf(admin);

        vm.prank(admin);
        vault.fundVault(amount);

        assertEq(usdc.balanceOf(address(vault)), vaultBefore + amount);
        assertEq(usdc.balanceOf(admin), adminBefore - amount);
    }

    function test_fundVault_increments_totalFunded() public {
        vm.prank(admin);
        vault.fundVault(1_000e6);
        assertEq(vault.totalFunded(), 1_000e6);
    }

    function test_fundVault_two_calls_accumulate() public {
        vm.startPrank(admin);
        vault.fundVault(300e6);
        vault.fundVault(200e6);
        vm.stopPrank();
        assertEq(vault.totalFunded(), 500e6);
    }

    function test_fundVault_emits_VaultFunded() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit VaultFunded(admin, 750e6, 750e6);

        vm.prank(admin);
        vault.fundVault(750e6);
    }

    function test_fundVault_reverts_when_not_owner() public {
        usdc.mint(stranger, 100e6);
        vm.startPrank(stranger);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert();
        vault.fundVault(100e6);
        vm.stopPrank();
    }

    function test_fundVault_reverts_when_paused() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vm.expectRevert();
        vault.fundVault(100e6);
    }

    function test_fundVault_reverts_on_zero_amount() public {
        vm.prank(admin);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.fundVault(0);
    }

    /// @notice The critical invariant · fundVault must NEVER touch user _balances.
    /// @dev    fundVault is the "generic backing" entry point: it adds Vault-held
    ///         USDC that can be paid out to any user via PLP.creditToUser, but the
    ///         act of funding creates no user-side claim. If this ever flipped, a
    ///         Primit-ops "restock the vault" call would silently credit itself,
    ///         and the invariant Σ _balances ≤ Vault USDC would collapse in the
    ///         other direction.
    function test_fundVault_does_not_touch_user_balances() public {
        address userA = address(0x1111);
        address userB = address(0x2222);

        uint256 userABefore = vault.balances(userA);
        uint256 userBBefore = vault.balances(userB);
        uint256 adminBefore = vault.balances(admin);
        uint256 totalDepositsBefore = vault.totalDeposits();

        vm.prank(admin);
        vault.fundVault(2_500e6);

        assertEq(vault.balances(userA), userABefore, "userA _balances must not change");
        assertEq(vault.balances(userB), userBBefore, "userB _balances must not change");
        assertEq(vault.balances(admin), adminBefore, "admin _balances must not change (funder is NOT a user)");
        assertEq(vault.totalDeposits(), totalDepositsBefore, "totalDeposits must not change (fundVault is not a deposit)");
    }

    /// @notice A newly-funded Vault should let PLP credit a user beyond their
    ///         deposit principal without becoming insolvent.
    /// @dev    Not exercising the full PLP path here (that lives in plp_contract
    ///         tests); we only assert that after fundVault, the Vault holds
    ///         enough USDC that a subsequent creditToUser + user-driven
    ///         withdrawFull could succeed — i.e. `usdc.balanceOf(vault) >=
    ///         Σ _balances + credit` remains true.
    function test_fundVault_creates_headroom_for_profit_credit() public {
        // User deposits 100 USDC through the normal path.
        usdc.mint(user, 200e6);
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(100e6, bytes32(0));
        vm.stopPrank();

        // Owner funds 500 USDC of generic backing.
        vm.prank(admin);
        vault.fundVault(500e6);

        // Invariant · Vault holds 100 + 500 = 600 USDC; sum of user _balances is
        // just 100 (only the deposit). Headroom for future credit = 500.
        assertEq(usdc.balanceOf(address(vault)), 600e6);
        assertEq(vault.balances(user), 100e6);
        assertEq(vault.totalFunded(), 500e6);
    }
}
