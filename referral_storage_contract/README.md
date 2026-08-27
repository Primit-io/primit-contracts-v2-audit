# ReferralStorage Foundry 项目

该目录是对 Arbitrum One 上已验证合约 `0x53459bc2848b3950695cd07bde2e2a34ec988e48` 的 Foundry 可构建版本还原。

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
- `REFERRAL_STORAGE_ADDRESS`
- `VAULT_ADDRESS`
- `REBATE_DISTRIBUTOR_ADDRESS`

本地 `.env` 有意移除了部署结果快照和其他未使用字段。当前已部署地址统一记录在下方，而不再重复写入 `.env`。

## 部署

在 Arbitrum Sepolia 上部署：

```bash
forge script script/Deploy.s.sol:DeployReferralStorageSepolia \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

在 Arbitrum One 上部署：

```bash
forge script script/Deploy.s.sol:DeployReferralStorageMainnet \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

在 `Vault` 和 `RebateDistributor` 部署完成后，执行 handler role 授权：

```bash
forge script script/Deploy.s.sol:GrantHandlerRoles \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

## 当前 Arbitrum Sepolia 地址

- `ReferralStorage` proxy：`0x064b26627f6a89D364Cdc6E4b760ACf833B99D5C`
- `ReferralStorage` implementation：`0x9365bB2F908b64f29b86Bca9b25BD40D557B196d`

## 备注

- `ReferralStorage` 应当先于 `Vault` 和 `RebateDistributor` 部署。
- 部署脚本现在会发布 UUPS implementation，并通过 `ERC1967Proxy` 挂载代理。
- 升级使用 `forge script script/Deploy.s.sol:UpgradeReferralStorage --broadcast`，目标地址为 `REFERRAL_STORAGE_ADDRESS`。
