# Vault Foundry 项目

该目录是对 Arbitrum One 上已验证合约 `0xC43B512C4285DF21E7a64505e0Df1d1b85140d1c` 的 Foundry 可构建版本还原。

## 目录结构

- `src/contracts/core/vault/Vault.sol`：主合约
- `src/contracts/interfaces/`：本地接口
- `src/contracts/libraries/`：本地库
- `src/contracts/referral/`：本地 referral 接口
- `src/node_modules/@openzeppelin/`：从验证器导出的 OpenZeppelin 源码
- `abi.json`：合约 ABI
- `address.json`：地址元数据
- `smart_contract.json`：来自 Blockscout 的验证载荷
- `runtime_bytecode.txt`：链上部署字节码

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
- `SIGNER_ADDRESS`
- Sepolia 使用 `USDT_TOKEN_ADDRESS`，主网使用 `MAINNET_USDT_ADDRESS`
- Sepolia 使用 `REFERRAL_STORAGE_ADDRESS`，主网使用 `MAINNET_REFERRAL_STORAGE_ADDRESS`
- 升级操作需要 `VAULT_ADDRESS`
- `EIP712_DOMAIN_NAME`
- `EIP712_DOMAIN_VERSION`

本地 `.env` 有意移除了 implementation 引用和重复的部署说明。当前已部署地址统一记录在下方，而不再重复写入 `.env`。

## 部署

Arbitrum Sepolia：

```bash
forge script script/Deploy.s.sol:DeployVaultSepolia \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

Arbitrum One：

```bash
forge script script/Deploy.s.sol:DeployVaultMainnet \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

## 当前 Arbitrum Sepolia 地址

- `Vault` proxy：`0x05877bfc766a9c6B5E68aEe49812b1ce20e20D56`
- `Vault` implementation：`0xa11B6BB4CFd107fcC93D9025155A0e7d418d4755`

## 备注

- 编译参数与验证元数据一致：Solidity `0.8.20`、优化器 `200` runs、`shanghai` EVM、`viaIR = false`。
- 部署脚本现在会发布 UUPS implementation，并通过 `ERC1967Proxy` 挂载代理。
- 升级使用 `forge script script/Deploy.s.sol:UpgradeVault --broadcast`，目标地址为 `VAULT_ADDRESS`。
- 升级脚本会调用一次 reinitializer，把 `EIP712_DOMAIN_VERSION` 持久化到 proxy 存储中。
