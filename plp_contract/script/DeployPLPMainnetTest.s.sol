// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {DeployPLP} from "./DeployPLP.s.sol";
import {BufferPool} from "../src/BufferPool.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";

/// @notice PLP v0.1 主网试部署 wrapper
/// @dev 从 env 读取所有 9 个参数,包一层 DeployPLP。
///      用途:v0.1 试部署,验证 script + hard checks + Snowtrace verify。
///      v0.2 起需要:1) VAULT 升级加 debitFromUser/creditToUser,2) 独立 SIGNER,3) 转 owner 给 OneKey。
///
/// 使用方法:
///   1. 设置 env:USDC / VAULT / PLP_ADMIN / PLP_OPERATOR / PLP_SIGNER /
///                VAULT_SIGNER / LEAKED_ADMIN / BUFFER_OWNER / VAULT_OWNER
///   2. forge script script/DeployPLPMainnetTest.s.sol:DeployPLPMainnetTest \
///          --rpc-url $AVAX_MAINNET_RPC_URL --broadcast --private-key $KEY
contract DeployPLPMainnetTest is Script {
    function run() external returns (BufferPool bp, LiquidityVault plp) {
        DeployPLP inner = new DeployPLP(
            vm.envAddress("USDC"),
            vm.envAddress("VAULT"),
            vm.envAddress("PLP_ADMIN"),
            vm.envAddress("PLP_OPERATOR"),
            vm.envAddress("PLP_SIGNER"),
            vm.envAddress("VAULT_SIGNER"),
            vm.envAddress("LEAKED_ADMIN"),
            vm.envAddress("BUFFER_OWNER"),
            vm.envAddress("VAULT_OWNER")
        );
        (bp, plp) = inner.run();
        console2.log("BufferPool deployed at:", address(bp));
        console2.log("LiquidityVault deployed at:", address(plp));
    }
}
