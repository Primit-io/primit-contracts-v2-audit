# PLP Contract (Primit Liquidity Provider)

> **Sprint**: SPRINT-PLP-V1-2026-0713
> **License**: MIT(与 EarnProduct 一致的自有许可,**不含任何 GMX BUSL 代码**)
> **Architecture**: 独立合约 + Vault.sol 白名单授权 + TDD 严格三段循环
> **Reference**: `../earn_contract/src/EarnProduct.sol`(可读,MIT/自有)+ OpenZeppelin(MIT/Apache)

## BUSL 合规声明

本合约**完全独立编写**,不含任何来自 GMX V2 / gmx-synthetics 的代码。GMX V2 为 BUSL-1.1 许可,当前禁止 production use,转 GPL v2 后仍传染,**PLP 与 GMX V2 代码零关联**。

编写过程遵循以下隔离:
- 参考文件 `refs/gmx-v2-reference/` 不在本仓库
- 编码时关闭所有 GMX 文件
- 命名与结构基于 EarnProduct + OpenZeppelin
- 主网上线前用 semantic-diff 证明独立

## 目录

```
plp_contract/
├── src/                        # 合约源码
├── test/                       # Foundry TDD 单测
├── script/                     # 部署脚本
├── lib/                        # OZ + forge-std(symlink to earn_contract)
├── foundry.toml
├── remappings.txt
└── README.md
```

## 开发命令

```bash
# 编译
forge build

# 全部测试(必须 全绿)
forge test

# 特定测试
forge test --match-test test_deposit_junior_3d_happy -vvv

# 覆盖率(要求 > 90%)
forge coverage

# 静态扫描
slither src/
```

## TDD 循环规则

```
🔴 RED    → 先写测试,run test 必须 FAIL
🟢 GREEN  → 写最小实现让 test PASS
🔵 REFACTOR → 清理代码,test 仍 PASS
```

**禁止**:
- 先写实现再写测试
- 保留"参考代码"改写(必须 delete)
- 跳过 RED 直接 GREEN
- Test 立刻 pass(证明没 fail 就没测到)

## Commit 规范

```
test(plp): red - <what should behave>
feat(plp): green - <minimal impl to pass>
refactor(plp): <what cleaned up>
```
