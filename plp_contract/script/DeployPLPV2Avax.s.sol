// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BufferPool} from "../src/BufferPool.sol";
import {LiquidityVault} from "../src/LiquidityVault.sol";

/// @notice V2 · Deploy PLP LiquidityVault (UUPS Proxy) + BufferPool (direct) on AVAX
///
/// Env:
///   PRIVATE_KEY         = deployer EOA (V2 hot key 0x2821c28b…)
///   USDC_ADDRESS        = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E
///   VAULT_ADDRESS       = V2 Vault Proxy (must be deployed first)
///   PLP_ADMIN           = ADMIN_ROLE + DEFAULT_ADMIN_ROLE holder
///   PLP_OPERATOR        = OPERATOR_ROLE holder
///   PLP_SIGNER          = SIGNER_ROLE holder
///   PLP_BUFFER_OWNER    = BufferPool Ownable owner
contract DeployPLPV2Avax is Script {
    address constant LEAKED_ADMIN = 0xadFF12DFE7C8992F9e97083838273a20B3B44E40;
    address constant KNOWN_COMPROMISED_ADMIN_1 = 0xF0cB036c96A7118d879Cf3a9e39bdC4Ee1D1b4D8;
    address constant KNOWN_COMPROMISED_ADMIN_2 = 0xa8549df5A5b2402807C183dD25E68AEE3f0Cc4BA;
    address constant EXPECTED_USDC_MAINNET = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    uint256 constant AVAX_MAINNET_CHAINID = 43_114;
    uint256 constant FUJI_CHAINID = 43_113;

    function run() external returns (address bufferPool, address plpImpl, address plpProxy) {
        uint256 chainId = block.chainid;
        require(chainId == AVAX_MAINNET_CHAINID || chainId == FUJI_CHAINID, "DeployPLPV2Avax: AVAX only");

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address plpAdmin = vm.envAddress("PLP_ADMIN");
        address plpOperator = vm.envAddress("PLP_OPERATOR");
        address plpSigner = vm.envAddress("PLP_SIGNER");
        address bufferOwner = vm.envAddress("PLP_BUFFER_OWNER");

        _checkAddr("deployer", deployer);
        _checkAddr("PLP_ADMIN", plpAdmin);
        _checkAddr("PLP_OPERATOR", plpOperator);
        _checkAddr("PLP_SIGNER", plpSigner);
        _checkAddr("PLP_BUFFER_OWNER", bufferOwner);

        if (chainId == AVAX_MAINNET_CHAINID) {
            require(usdc == EXPECTED_USDC_MAINNET, "DeployPLPV2Avax: mainnet must use native USDC");
        }

        console2.log("=== DeployPLPV2Avax ===");
        console2.log("  chainid       :", chainId);
        console2.log("  deployer      :", deployer);
        console2.log("  usdc          :", usdc);
        console2.log("  vault         :", vaultAddr);
        console2.log("  PLP_ADMIN     :", plpAdmin);
        console2.log("  PLP_OPERATOR  :", plpOperator);
        console2.log("  PLP_SIGNER    :", plpSigner);
        console2.log("  BUFFER_OWNER  :", bufferOwner);

        vm.startBroadcast(deployerPk);

        BufferPool bp = new BufferPool(usdc, bufferOwner);

        LiquidityVault implContract = new LiquidityVault();
        bytes memory initData = abi.encodeCall(
            LiquidityVault.initialize,
            (usdc, vaultAddr, plpAdmin, plpOperator, plpSigner)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implContract), initData);

        vm.stopBroadcast();

        bufferPool = address(bp);
        plpImpl = address(implContract);
        plpProxy = address(proxyContract);

        console2.log("  BufferPool    :", bufferPool);
        console2.log("  PLP impl      :", plpImpl);
        console2.log("  PLP Proxy     :", plpProxy);
    }

    function _checkAddr(string memory label, address a) internal pure {
        require(a != address(0), string.concat("DeployPLPV2Avax: zero ", label));
        require(a != LEAKED_ADMIN, string.concat("SEC-002: ", label, " == leaked ADMIN"));
        require(
            a != KNOWN_COMPROMISED_ADMIN_1 && a != KNOWN_COMPROMISED_ADMIN_2,
            string.concat("D7 SEC: ", label, " == KNOWN_COMPROMISED_ADMIN")
        );
    }
}
