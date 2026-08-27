# Rebate Distributor Foundry 项目

该目录是对 Arbitrum One 上已验证合约 `0xCC0b6330A340e177c387F3b7E9aaDc7c882b8709` 的 Foundry 可构建版本还原。

## 构建

```bash
forge build
```

## 环境变量

部署前请先复制模板：

```bash
cp .env.example .env
```

部署所需字段：

- `DEPLOYER_PRIVATE_KEY`
- `ADMIN_PRIVATE_KEY`
- `ADMIN_ADDRESS`
- Sepolia 使用 `USDT_TOKEN_ADDRESS`，主网使用 `MAINNET_USDT_ADDRESS`
- Sepolia 使用 `VAULT_ADDRESS`，主网使用 `MAINNET_VAULT_ADDRESS`
- `SIGNER_ADDRESS`
- Sepolia 使用 `REFERRAL_STORAGE_ADDRESS`，主网使用 `MAINNET_REFERRAL_STORAGE_ADDRESS`
- 升级操作需要 `REBATE_DISTRIBUTOR_ADDRESS`
- `EIP712_REFERRAL_DOMAIN_NAME`
- `EIP712_REFERRAL_DOMAIN_VERSION`

本地 `.env` 有意移除了 implementation 引用和重复的部署说明。当前已部署地址统一记录在下方，而不再重复写入 `.env`。

## 部署

Arbitrum Sepolia：

```bash
forge script script/Deploy.s.sol:DeployRebateDistributorSepolia \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

Arbitrum One：

```bash
forge script script/Deploy.s.sol:DeployRebateDistributorMainnet \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

## 当前 Arbitrum Sepolia 地址

- `RebateDistributor` proxy：`0x6210719f18dBF980C925602550bD138838fD8289`
- `RebateDistributor` implementation：`0x309479379e1477737f4B9FfdB37fF46BDFe2E5B3`

## 备注

- `RebateDistributor` 同时依赖 `Vault` 和 `ReferralStorage`。
- 部署脚本现在会发布 UUPS implementation，并通过 `ERC1967Proxy` 挂载代理。
- 升级使用 `forge script script/Deploy.s.sol:UpgradeRebateDistributor --broadcast`，目标地址为 `REBATE_DISTRIBUTOR_ADDRESS`。
- 升级脚本会调用一次 reinitializer，把 `EIP712_REFERRAL_DOMAIN_VERSION` 持久化到 proxy 存储中。
