// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployPLP} from "../script/DeployPLP.s.sol";
import {BufferPool} from "../src/BufferPool.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";

/// @notice DeployPLP 部署脚本集成测试
/// @dev 用 integration test 驱动 script 正确性:hard checks + 顺序 + 初始化。
///      主网上线前部署走 script,test 用 fork 方式验证真实环境行为。
contract DeployPLPTest is Test {
    address constant USDC = address(0xB01);
    address constant VAULT = address(0xB02);
    address constant ADMIN = address(0xA01);
    address constant OPERATOR = address(0xA02);
    address constant SIGNER = address(0xA03); // PLP EIP-712 signer
    address constant VAULT_SIGNER = address(0xA04); // Vault 后端签名者(不同于 PLP)
    address constant LEAKED_ADMIN = address(0xBAD001); // SEC-002 泄露地址
    address constant BUFFER_OWNER = address(0xC01);
    address constant VAULT_OWNER = address(0xC02);

    // ================================================================
    // 🔴 RED #54: DeployPLP.run() 返回 (BufferPool, LiquidityVault) 两个非零地址
    // ================================================================

    function test_deploy_returns_two_deployed_addresses() public {
        DeployPLP deployer = new DeployPLP(
            USDC,
            VAULT,
            ADMIN,
            OPERATOR,
            SIGNER,
            VAULT_SIGNER,
            LEAKED_ADMIN,
            BUFFER_OWNER,
            VAULT_OWNER
        );
        (BufferPool bp, LiquidityVault plp) = deployer.run();
        assertTrue(address(bp) != address(0));
        assertTrue(address(plp) != address(0));
    }

    // ================================================================
    // 🔴 RED #57: hard check — BufferPool owner == Vault owner 时 revert(D-PT-6)
    // ================================================================

    function test_deploy_reverts_buffer_owner_collision() public {
        // BufferPool owner 与 Vault owner 是同一把 key 违反 SEC-002 教训
        address sameOwner = address(0xC03);
        DeployPLP deployer = new DeployPLP(
            USDC,
            VAULT,
            ADMIN,
            OPERATOR,
            SIGNER,
            VAULT_SIGNER,
            LEAKED_ADMIN,
            sameOwner,   // buffer owner
            sameOwner    // vault owner(冲突)
        );
        vm.expectRevert(DeployPLP.OwnerCollision.selector);
        deployer.run();
    }

    // ================================================================
    // 🔴 RED #56: hard check — 任何角色地址 == SEC-002 leaked ADMIN 时 revert
    // ================================================================

    function test_deploy_reverts_sec_002_collision_signer() public {
        DeployPLP deployer = new DeployPLP(
            USDC,
            VAULT,
            ADMIN,
            OPERATOR,
            LEAKED_ADMIN,  // signer == leaked
            VAULT_SIGNER,
            LEAKED_ADMIN,
            BUFFER_OWNER,
            VAULT_OWNER
        );
        vm.expectRevert(DeployPLP.Sec002Collision.selector);
        deployer.run();
    }

    // ================================================================
    // 🔴 RED #55: hard check — PLP signer == Vault signer 时 revert(D-PT-4)
    // ================================================================

    function test_deploy_reverts_signer_collision() public {
        // SIGNER == VAULT_SIGNER 意味着一把 key 双重用途,SEC-002 类风险
        address sameKey = address(0xA05);
        DeployPLP deployer = new DeployPLP(
            USDC,
            VAULT,
            ADMIN,
            OPERATOR,
            sameKey,       // PLP signer
            sameKey,       // Vault signer(冲突)
            LEAKED_ADMIN,
            BUFFER_OWNER,
            VAULT_OWNER
        );
        vm.expectRevert(DeployPLP.SignerCollision.selector);
        deployer.run();
    }
}
