// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  BufferPool
/// @notice PLP performance fee 缓冲基金(D-LP-7)。极端事件补偿 LP + 审计费开销。
/// @dev    v1 简化:单 owner 控制;v1.1 升级 Safe 多签 + Timelock 48h。
///         独立编写,不含任何 GMX BUSL 代码。
interface IERC20Min {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract BufferPool {
    error ZeroAddress();
    error NotOwner();

    event Disbursed(address indexed to, uint256 amount);

    address public immutable usdc;
    address public owner;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _usdc, address _owner) {
        if (_usdc == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        usdc = _usdc;
        owner = _owner;
    }

    /// @notice owner 从 BufferPool 划拨 USDC.e(v1.1 升级 Timelock 48h)
    function disburse(address to, uint256 amount) external onlyOwner {
        IERC20Min(usdc).transfer(to, amount);
        emit Disbursed(to, amount);
    }
}
