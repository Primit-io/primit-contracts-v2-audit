// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface ILiquidityVault {
    function withdraw(uint256 shares, uint8 tier, uint256 deadline, bytes calldata signature) external;
    function plpShares(address user, uint8 tier) external view returns (uint256);
    function nonces(address user) external view returns (uint256);
    function WITHDRAW_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// @notice DEV E2E · 本地 sign PLP.withdraw(绕开 backend hardcoded nonce=0)
/// @dev env: PRIVATE_KEY / PLP_ADDRESS / WITHDRAW_SHARES / WITHDRAW_TIER
///      dev mode 下 hot EOA 同时是 SIGNER_ROLE + msg.sender,可本地签
contract PlpWithdrawE2ELocal is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(pk);
        address plp = vm.envAddress("PLP_ADDRESS");
        uint256 shares = vm.envUint("WITHDRAW_SHARES");
        uint8 tier = uint8(vm.envUint("WITHDRAW_TIER"));

        ILiquidityVault v = ILiquidityVault(plp);
        uint256 nonce = v.nonces(user);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 typehash = v.WITHDRAW_TYPEHASH();
        bytes32 domainSep = v.DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(abi.encode(typehash, user, shares, tier, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encodePacked(r, s, vv);

        console2.log("=== PlpWithdrawE2ELocal ===");
        console2.log("  user:", user);
        console2.log("  plp:", plp);
        console2.log("  shares:", shares);
        console2.log("  tier:", tier);
        console2.log("  nonce (from chain):", nonce);
        console2.log("  deadline:", deadline);
        console2.log("  before | shares[tier]:", v.plpShares(user, tier));

        vm.startBroadcast(pk);
        v.withdraw(shares, tier, deadline, sig);
        vm.stopBroadcast();

        console2.log("  after  | shares[tier]:", v.plpShares(user, tier));
        console2.log("  after  | nonce:", v.nonces(user));
    }
}
