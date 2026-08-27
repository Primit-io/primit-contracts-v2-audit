// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface ILiquidityVault {
    function deposit(uint256 amount, uint8 tier, uint256 deadline, bytes calldata signature) external;
    function plpShares(address user, uint8 tier) external view returns (uint256);
    function nonces(address user) external view returns (uint256);
}

/// @notice DEV E2E · PLP.deposit(amount, tier, deadline, signature) 一梭子
/// @dev env: PRIVATE_KEY / PLP_ADDRESS / DEPOSIT_AMOUNT / DEPOSIT_TIER / DEPOSIT_DEADLINE / DEPOSIT_SIG
contract PlpDepositE2E is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(pk);
        address plp = vm.envAddress("PLP_ADDRESS");
        uint256 amount = vm.envUint("DEPOSIT_AMOUNT");
        uint8 tier = uint8(vm.envUint("DEPOSIT_TIER"));
        uint256 deadline = vm.envUint("DEPOSIT_DEADLINE");
        bytes memory sig = vm.envBytes("DEPOSIT_SIG");

        console2.log("=== PlpDepositE2E ===");
        console2.log("  user:", user);
        console2.log("  plp:", plp);
        console2.log("  amount:", amount);
        console2.log("  tier:", tier);
        console2.log("  deadline:", deadline);
        console2.log("  before | shares[tier]:", ILiquidityVault(plp).plpShares(user, tier));
        console2.log("  before | nonce:", ILiquidityVault(plp).nonces(user));

        vm.startBroadcast(pk);
        ILiquidityVault(plp).deposit(amount, tier, deadline, sig);
        vm.stopBroadcast();

        console2.log("  after  | shares[tier]:", ILiquidityVault(plp).plpShares(user, tier));
        console2.log("  after  | nonce:", ILiquidityVault(plp).nonces(user));
    }
}
