// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface ILiquidityVault {
    function withdraw(uint256 shares, uint8 tier, uint256 deadline, bytes calldata signature) external;
    function plpShares(address user, uint8 tier) external view returns (uint256);
    function nonces(address user) external view returns (uint256);
}

/// @notice DEV E2E · PLP.withdraw 一梭子
/// env: PRIVATE_KEY / PLP_ADDRESS / WITHDRAW_SHARES / WITHDRAW_TIER / WITHDRAW_DEADLINE / WITHDRAW_SIG
contract PlpWithdrawE2E is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(pk);
        address plp = vm.envAddress("PLP_ADDRESS");
        uint256 shares = vm.envUint("WITHDRAW_SHARES");
        uint8 tier = uint8(vm.envUint("WITHDRAW_TIER"));
        uint256 deadline = vm.envUint("WITHDRAW_DEADLINE");
        bytes memory sig = vm.envBytes("WITHDRAW_SIG");

        console2.log("=== PlpWithdrawE2E ===");
        console2.log("  user:", user);
        console2.log("  plp:", plp);
        console2.log("  shares:", shares);
        console2.log("  tier:", tier);
        console2.log("  before | shares[tier]:", ILiquidityVault(plp).plpShares(user, tier));

        vm.startBroadcast(pk);
        ILiquidityVault(plp).withdraw(shares, tier, deadline, sig);
        vm.stopBroadcast();

        console2.log("  after  | shares[tier]:", ILiquidityVault(plp).plpShares(user, tier));
    }
}
