// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/contracts/recorder/TradeRecorder.sol";

contract TradeRecorderTest is Test {
    TradeRecorder rec;
    address owner = address(0xA11CE);
    address recorder = address(0xB0B);
    address taker = address(0x1111);
    address maker = address(0x2222);

    event TradeRecorded(
        bytes32 indexed tradeId,
        address indexed taker,
        address indexed maker,
        string symbol,
        uint8 side,
        uint256 price,
        uint256 amount,
        int256 takerFee,
        int256 makerFee,
        bool isClose,
        uint64 filledAt
    );

    function setUp() public {
        vm.prank(owner);
        rec = new TradeRecorder(recorder);
    }

    function _one() internal view returns (TradeRecorder.TradeRecord[] memory) {
        TradeRecorder.TradeRecord[] memory rs = new TradeRecorder.TradeRecord[](1);
        rs[0] = TradeRecorder.TradeRecord({
            tradeId: keccak256("t1"),
            taker: taker,
            maker: maker,
            symbol: "BTC-PERP",
            side: 0,
            price: 65000 ether,
            amount: 1 ether,
            takerFee: 5 ether,
            makerFee: -1 ether,
            isClose: true,
            filledAt: uint64(1_700_000_000)
        });
        return rs;
    }

    function testRecorderCanEmit() public {
        vm.expectEmit(true, true, true, true);
        emit TradeRecorded(
            keccak256("t1"), taker, maker, "BTC-PERP", 0, 65000 ether, 1 ether, 5 ether, -1 ether, true, uint64(1_700_000_000)
        );
        vm.prank(recorder);
        rec.recordTrades(_one());
    }

    function testNonRecorderReverts() public {
        vm.prank(taker);
        vm.expectRevert(TradeRecorder.NotRecorder.selector);
        rec.recordTrades(_one());
    }

    function testOwnerCanRotateRecorder() public {
        address next = address(0xCAFE);
        vm.prank(owner);
        rec.setRecorder(next);
        assertEq(rec.recorder(), next);
        vm.prank(next);
        rec.recordTrades(_one()); // no revert
    }

    function testNonOwnerCannotRotate() public {
        vm.prank(taker);
        vm.expectRevert(TradeRecorder.NotOwner.selector);
        rec.setRecorder(taker);
    }

    function testConstructorRejectsZeroRecorder() public {
        vm.expectRevert(TradeRecorder.ZeroAddress.selector);
        new TradeRecorder(address(0));
    }
}
