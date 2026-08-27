// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BufferPool} from "../src/BufferPool.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";

/// @notice PLP v1 部署脚本
/// @dev 部署顺序:BufferPool → LiquidityVault → initialize。
///      Hard checks(D-PT-7):防止 signer 冲突 / SEC-002 leaked ADMIN 复用 / owner 冲突。
///      主网调用示例:
///        forge script script/DeployPLP.s.sol --rpc-url $AVAX_MAINNET_RPC_URL \
///          --broadcast --sender $DEPLOYER_ADDRESS --private-key $DEPLOYER_KEY
contract DeployPLP is Script {
    error SignerCollision();
    error Sec002Collision();
    error OwnerCollision();

    address public immutable usdc;
    address public immutable vault;
    address public immutable admin;
    address public immutable operator;
    address public immutable signer;
    address public immutable vaultSigner;
    address public immutable leakedAdmin;
    address public immutable bufferOwner;
    address public immutable vaultOwner;

    constructor(
        address _usdc,
        address _vault,
        address _admin,
        address _operator,
        address _signer,
        address _vaultSigner,
        address _leakedAdmin,
        address _bufferOwner,
        address _vaultOwner
    ) {
        usdc = _usdc;
        vault = _vault;
        admin = _admin;
        operator = _operator;
        signer = _signer;
        vaultSigner = _vaultSigner;
        leakedAdmin = _leakedAdmin;
        bufferOwner = _bufferOwner;
        vaultOwner = _vaultOwner;
    }

    function run() external returns (BufferPool, LiquidityVault) {
        // Hard check 1(D-PT-7):PLP signer 与 Vault signer 不能是同一把 key
        if (signer == vaultSigner) revert SignerCollision();

        // Hard check 2(SEC-2026-0428-002):任何 PLP 角色地址禁止 == 已泄露 ADMIN
        if (admin == leakedAdmin) revert Sec002Collision();
        if (operator == leakedAdmin) revert Sec002Collision();
        if (signer == leakedAdmin) revert Sec002Collision();
        if (bufferOwner == leakedAdmin) revert Sec002Collision();

        // Hard check 3(D-PT-6):BufferPool owner 与 Vault owner 密钥不同人
        if (bufferOwner == vaultOwner) revert OwnerCollision();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        BufferPool bp = new BufferPool(usdc, bufferOwner);
        LiquidityVault plp = new LiquidityVault();
        plp.initialize(usdc, vault, admin, operator, signer);
        vm.stopBroadcast();
        return (bp, plp);
    }
}
