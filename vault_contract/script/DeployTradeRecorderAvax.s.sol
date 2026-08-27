// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/contracts/recorder/TradeRecorder.sol";

/// Deploy TradeRecorder to Avalanche C-Chain (43114).
/// Required env:
///   RECORDER_ADDRESS  = official EOA that will call recordTrades (pays gas)
///   PRIVATE_KEY       = deployer key (becomes owner; may differ from recorder)
contract DeployTradeRecorderAvax is Script {
    function run() external {
        require(block.chainid == 43114, "TradeRecorder: expected Avalanche C-Chain 43114");
        address recorder = vm.envAddress("RECORDER_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        TradeRecorder rec = new TradeRecorder(recorder);
        vm.stopBroadcast();

        console.log("TradeRecorder deployed at:", address(rec));
        console.log("owner:", rec.owner());
        console.log("recorder:", rec.recorder());
    }
}
