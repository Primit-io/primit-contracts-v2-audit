// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

/// @notice DEV ONLY · 用 hot EOA 一把 key 完成 USDC.approve + Vault.deposit 两笔 tx,
///         把 USDC.e 存到 Vault._balances,让 PLP.deposit 有钱可以 debitFromUser。
/// @dev env: PRIVATE_KEY / USDC_ADDRESS / VAULT_ADDRESS / DEPOSIT_AMOUNT (raw 6-decimal wei)
interface IERC20Min {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IVaultMin {
    function deposit(uint256 amount, bytes32 referralCode) external;
    function getBalance(address user) external view returns (uint256);
}

contract PreDepositDevMode is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(pk);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        uint256 amount = vm.envUint("DEPOSIT_AMOUNT");

        console2.log("=== PreDepositDevMode ===");
        console2.log("  user:", user);
        console2.log("  usdc:", usdc);
        console2.log("  vault:", vault);
        console2.log("  amount (raw wei):", amount);
        console2.log("  before | wallet USDC.e:", IERC20Min(usdc).balanceOf(user));
        console2.log("  before | vault balance:", IVaultMin(vault).getBalance(user));

        vm.startBroadcast(pk);
        IERC20Min(usdc).approve(vault, amount);
        IVaultMin(vault).deposit(amount, bytes32(0));
        vm.stopBroadcast();

        console2.log("  after  | wallet USDC.e:", IERC20Min(usdc).balanceOf(user));
        console2.log("  after  | vault balance:", IVaultMin(vault).getBalance(user));
    }
}
