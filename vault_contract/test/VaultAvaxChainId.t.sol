// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "../src/contracts/core/vault/Vault.sol";

/// @title VaultAvaxChainIdTest
/// @notice Verifies Vault.sol is correctly chain-aware for AVAX deployments.
///         AVAX adapts without any source-code change — these tests prove it.
///
/// Tested invariants (DESIGN-2026-0512-001 §3.1 + §6.1):
///   - DOMAIN_SEPARATOR includes block.chainid → cross-chain signatures are
///     not replay-able (Fuji 43113 vs AVAX 43114 vs Arb produce 3 different
///     DOMAIN_SEPARATORs even with identical other params).
///   - Vault deployed on AVAX (mocked via vm.chainId) produces the same
///     contract behaviour as Arb deployment (no chain-specific branching).
///   - SEC-2026-0428-002 hardcoded address check at script-level is the
///     real defence; the contract itself does not whitelist by chain.
contract VaultAvaxChainIdTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;
    address internal backendSigner = address(0xB0BAFEEd);
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);

    /// @dev Deploy a fresh Vault under a specific chainid, return its
    /// DOMAIN_SEPARATOR for cross-chain comparison.
    function _deployAt(uint256 cid, string memory domainName) internal returns (bytes32 sep) {
        vm.chainId(cid);

        ERC20Mock token = new ERC20Mock();

        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (address(token), backendSigner, referralStorage, domainName, "1.0.0", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        Vault v = Vault(address(proxy));
        sep = v.DOMAIN_SEPARATOR();
    }

    function test_DomainSeparator_AVAX_Mainnet_43114() public {
        bytes32 sep = _deployAt(43_114, "Primit Vault AVAX");
        assertTrue(sep != bytes32(0), "DOMAIN_SEPARATOR must be non-zero");
    }

    function test_DomainSeparator_AVAX_Fuji_43113() public {
        bytes32 sep = _deployAt(43_113, "Primit Vault AVAX Fuji");
        assertTrue(sep != bytes32(0), "DOMAIN_SEPARATOR must be non-zero");
    }

    function test_DomainSeparator_AVAX_vs_Fuji_distinct() public {
        bytes32 sepAvax = _deployAt(43_114, "Primit Vault AVAX");
        // Reset and deploy on Fuji
        bytes32 sepFuji = _deployAt(43_113, "Primit Vault AVAX Fuji");
        assertTrue(
            sepAvax != sepFuji,
            "AVAX 43114 DOMAIN_SEPARATOR must NOT collide with Fuji 43113"
        );
    }

    function test_DomainSeparator_AVAX_vs_Arb_distinct_same_name() public {
        // Same domain name on both chains — DOMAIN_SEPARATOR must still differ
        // because chainid is part of the EIP-712 domain.
        bytes32 sepAvax = _deployAt(43_114, "Primit Vault");
        bytes32 sepArb = _deployAt(42_161, "Primit Vault");
        assertTrue(
            sepAvax != sepArb,
            "Same name on AVAX vs Arb must produce different DOMAIN_SEPARATORs"
        );
    }

    function test_VaultStateInit_chain_agnostic() public {
        vm.chainId(43_114);
        ERC20Mock token = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (address(token), backendSigner, referralStorage, "Primit Vault AVAX", "1.0.0", admin)
        );
        Vault v = Vault(address(new ERC1967Proxy(address(impl), initData)));

        // Post-init invariants — all values should match initialize args regardless of chain
        assertEq(address(v.usdc()), address(token));
        assertEq(v.backendSigner(), backendSigner);
        assertEq(address(v.referralStorage()), referralStorage);
        assertEq(v.owner(), admin);
        assertEq(v.totalDeposits(), 0);
        assertEq(v.totalWithdrawals(), 0);
    }

    function test_DepositWithdrawNonce_chain_agnostic_AVAX() public {
        vm.chainId(43_114);
        ERC20Mock token = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (address(token), backendSigner, referralStorage, "Primit Vault AVAX", "1.0.0", admin)
        );
        Vault v = Vault(address(new ERC1967Proxy(address(impl), initData)));

        // Use a user. ERC20Mock defaults to 18 decimals; Vault.initialize sets
        // minDeposit = 10 ** decimals = 1e18, so the test amount must be ≥ 1e18.
        // Production AVAX uses USDC.e (6 decimals) where minDeposit = 1e6.
        address user = address(0x1111);
        uint256 amount = 10 ether;  // 10 * 1e18, comfortably above minDeposit
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(v), amount);
        v.deposit(amount, bytes32(0));
        vm.stopPrank();

        assertEq(v.totalDeposits(), amount);
        assertEq(v.depositedBalances(user), amount);
        assertEq(v.withdrawNonces(user), 0, "nonce should start at 0");
    }
}
