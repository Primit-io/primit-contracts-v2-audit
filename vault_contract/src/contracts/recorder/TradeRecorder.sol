// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title TradeRecorder
/// @notice Storage-free public audit log of matched trades. Emits one
///         `TradeRecorded` event per record. Only the official `recorder`
///         EOA (which pays gas) may write; `owner` may rotate the recorder.
///         Fully isolated from the Vault; holds no funds.
contract TradeRecorder {
    address public owner;
    address public recorder;

    struct TradeRecord {
        bytes32 tradeId;
        address taker;
        address maker;
        string  symbol;
        uint8   side;      // 0 = buy, 1 = sell (taker perspective)
        uint256 price;     // fixed-point, 18 decimals
        uint256 amount;    // fixed-point, 18 decimals
        int256  takerFee;  // fixed-point, 18 decimals, may be negative
        int256  makerFee;
        bool    isClose;   // taker order was reduce-only
        uint64  filledAt;  // unix seconds
    }

    event TradeRecorded(
        bytes32 indexed tradeId,
        address indexed taker,
        address indexed maker,
        string  symbol,
        uint8   side,
        uint256 price,
        uint256 amount,
        int256  takerFee,
        int256  makerFee,
        bool    isClose,
        uint64  filledAt
    );
    event RecorderUpdated(address indexed previous, address indexed next);

    error NotOwner();
    error NotRecorder();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRecorder() {
        if (msg.sender != recorder) revert NotRecorder();
        _;
    }

    constructor(address _recorder) {
        if (_recorder == address(0)) revert ZeroAddress();
        owner = msg.sender;
        recorder = _recorder;
        emit RecorderUpdated(address(0), _recorder);
    }

    /// @notice Rotate the recorder EOA (e.g. key rotation). Owner-only.
    function setRecorder(address _recorder) external onlyOwner {
        if (_recorder == address(0)) revert ZeroAddress();
        emit RecorderUpdated(recorder, _recorder);
        recorder = _recorder;
    }

    /// @notice Emit one `TradeRecorded` per record. Recorder-only. No storage.
    function recordTrades(TradeRecord[] calldata records) external onlyRecorder {
        for (uint256 i = 0; i < records.length; i++) {
            TradeRecord calldata r = records[i];
            emit TradeRecorded(
                r.tradeId,
                r.taker,
                r.maker,
                r.symbol,
                r.side,
                r.price,
                r.amount,
                r.takerFee,
                r.makerFee,
                r.isClose,
                r.filledAt
            );
        }
    }
}
