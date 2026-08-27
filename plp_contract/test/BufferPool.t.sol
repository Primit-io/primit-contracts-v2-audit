// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BufferPool} from "../src/BufferPool.sol";

/// @dev 最小 USDC mock,支持 transfer + balanceOf
contract UsdtMock {
    mapping(address => uint256) public balances;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "insufficient");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }
}

/// @notice PLP BufferPool 独立合约 TDD 测试套
/// @dev D-LP-7 Performance fee 10% 归 Buffer Pool。v1 简化为单 owner 控制。
///      v1.1 升级 Safe 多签 + Timelock 48h。
contract BufferPoolTest is Test {
    address constant USDC_MOCK = address(0xB01);
    address constant OWNER = address(0xA01);

    // 本地 event 复刻(Foundry 惯用)
    event Disbursed(address indexed to, uint256 amount);

    // ================================================================
    // 🔴 RED #49: BufferPool 部署后 owner() 返回构造时传入的地址
    // ================================================================

    function test_owner_is_constructor_arg() public {
        BufferPool bp = new BufferPool(USDC_MOCK, OWNER);
        assertEq(bp.owner(), OWNER);
    }

    // ================================================================
    // 🔴 RED #50: BufferPool 拒绝 zero owner 地址(防误部署)
    // ================================================================

    function test_constructor_reverts_zero_owner() public {
        vm.expectRevert(BufferPool.ZeroAddress.selector);
        new BufferPool(USDC_MOCK, address(0));
    }

    // ================================================================
    // 🔴 RED #51: BufferPool 拒绝 zero usdc 地址(防误部署)
    // ================================================================

    function test_constructor_reverts_zero_usdc() public {
        vm.expectRevert(BufferPool.ZeroAddress.selector);
        new BufferPool(address(0), OWNER);
    }

    // ================================================================
    // 🔴 RED #52: disburse 拒绝非 owner 调用者
    // ================================================================

    function test_disburse_reverts_non_owner() public {
        BufferPool bp = new BufferPool(USDC_MOCK, OWNER);
        address stranger = address(0xDEAD);
        address recipient = address(0xBEEF);
        vm.prank(stranger);
        vm.expectRevert(BufferPool.NotOwner.selector);
        bp.disburse(recipient, 1_000_000);
    }

    // ================================================================
    // 🔴 RED #53: disburse emit Disbursed(to, amount) 事件
    // ================================================================

    function test_disburse_emits_Disbursed_event() public {
        UsdtMock usdc = new UsdtMock();
        BufferPool bp = new BufferPool(address(usdc), OWNER);
        usdc.mint(address(bp), 1000 * 1e6);

        address recipient = address(0xBEEF);
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true, address(bp));
        emit Disbursed(recipient, 300 * 1e6);
        bp.disburse(recipient, 300 * 1e6);
    }
}
