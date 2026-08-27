// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/contracts/referral/ReferralStorage.sol";

contract DeployReferralStorageSepolia is Script {
    function run() external returns (ReferralStorage referralStorage) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ReferralStorage to Arbitrum Sepolia ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ReferralStorage implementation = new ReferralStorage();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ReferralStorage.initialize, (admin))
        );
        referralStorage = ReferralStorage(address(proxy));
        vm.stopBroadcast();

        console.log("ReferralStorage deployed at:", address(referralStorage));
        console.log("ReferralStorage implementation:", address(implementation));
    }
}

contract DeployReferralStorageMainnet is Script {
    function run() external returns (ReferralStorage referralStorage) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== Deploying ReferralStorage to Arbitrum One ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);
        ReferralStorage implementation = new ReferralStorage();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ReferralStorage.initialize, (admin))
        );
        referralStorage = ReferralStorage(address(proxy));
        vm.stopBroadcast();

        console.log("ReferralStorage deployed at:", address(referralStorage));
        console.log("ReferralStorage implementation:", address(implementation));
    }
}

contract GrantHandlerRoles is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address referralStorageAddress = vm.envAddress("REFERRAL_STORAGE_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address rebateDistributor = vm.envAddress("REBATE_DISTRIBUTOR_ADDRESS");

        console.log("=== Granting handler roles ===");
        console.log("ReferralStorage:", referralStorageAddress);
        console.log("Vault:", vault);
        console.log("RebateDistributor:", rebateDistributor);

        vm.startBroadcast(adminPrivateKey);

        ReferralStorage referralStorage = ReferralStorage(referralStorageAddress);
        referralStorage.grantHandlerRole(vault);
        referralStorage.grantHandlerRole(rebateDistributor);

        vm.stopBroadcast();

        console.log("Handler roles granted.");
    }
}

contract UpgradeReferralStorage is Script {
    function run() external returns (address implementation) {
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address referralStorageProxy = vm.envAddress("REFERRAL_STORAGE_ADDRESS");

        console.log("=== Upgrading ReferralStorage proxy ===");
        console.log("Proxy:", referralStorageProxy);
        console.log("Admin:", vm.addr(adminPrivateKey));

        vm.startBroadcast(adminPrivateKey);
        implementation = address(new ReferralStorage());
        ReferralStorage(payable(referralStorageProxy)).upgradeToAndCall(implementation, bytes(""));
        vm.stopBroadcast();

        console.log("New implementation:", implementation);
    }
}
