// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IVault.sol";

/**
 * @title SignatureVerifier
 * @notice Library for EIP-712 signature verification
 * @dev Provides utilities for verifying typed data signatures according to EIP-712
 * @dev Implements security best practices: signature length validation, zero address checks
 */
library SignatureVerifier {
    using ECDSA for bytes32;

    /// @notice ECDSA signature length (r: 32 bytes + s: 32 bytes + v: 1 byte)
    uint256 private constant SIGNATURE_LENGTH = 65;

    /// @notice Error thrown when signature length is invalid
    error InvalidSignatureLength(uint256 length);

    /// @notice Error thrown when recovered signer is zero address
    error InvalidSigner();

    /**
     * @notice Verify a withdrawal signature
     * @dev Validates signature length, recovers signer, and checks against expected signer
     * @param domainSeparator The EIP-712 domain separator
     * @param user The user address
     * @param amount The withdrawal amount
     * @param nonce The withdrawal nonce
     * @param deadline The signature deadline
     * @param signature The signature to verify (65 bytes: r + s + v)
     * @param expectedSigner The expected signer address
     * @return isValid Whether the signature is valid
     */
    function verifyWithdrawSignature(
        bytes32 domainSeparator,
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        // Validate signature length (must be 65 bytes: 32 bytes r + 32 bytes s + 1 byte v)
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        // Compute EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                user,
                amount,
                nonce,
                deadline
            )
        );

        // Compute EIP-712 message hash
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover signer from signature
        address signer = hash.recover(signature);

        // Check that signer is not zero address (ECDSA.recover can return address(0) for invalid signatures)
        if (signer == address(0)) {
            revert InvalidSigner();
        }

        // Verify signer matches expected signer
        return signer == expectedSigner;
    }

    /**
     * @notice Verify a rebate claim signature
     * @dev Validates signature length, recovers signer, and checks against expected signer
     * @param domainSeparator The EIP-712 domain separator
     * @param user The user address
     * @param amount The rebate amount
     * @param nonce The rebate nonce
     * @param deadline The signature deadline
     * @param signature The signature to verify (65 bytes: r + s + v)
     * @param expectedSigner The expected signer address
     * @return isValid Whether the signature is valid
     */
    function verifyClaimSignature(
        bytes32 domainSeparator,
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        // Validate signature length (must be 65 bytes: 32 bytes r + 32 bytes s + 1 byte v)
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        // Compute EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ClaimRebate(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                user,
                amount,
                nonce,
                deadline
            )
        );

        // Compute EIP-712 message hash
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover signer from signature
        address signer = hash.recover(signature);

        // Check that signer is not zero address (ECDSA.recover can return address(0) for invalid signatures)
        if (signer == address(0)) {
            revert InvalidSigner();
        }

        // Verify signer matches expected signer
        return signer == expectedSigner;
    }

    /**
     * @notice Compute EIP-712 domain separator
     * @param name The contract name
     * @param version The contract version
     * @param chainId The chain ID
     * @param verifyingContract The contract address
     * @return The domain separator
     */
    function computeDomainSeparator(
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    /**
     * @notice Verify a position-close audit-log signature
     * @dev EIP-712 typed-data signature authorising the on-chain audit emission
     *      for an off-chain perpetual position close. The signature is produced
     *      by the backend so the on-chain caller (the closing user) can submit
     *      a transaction and pay gas, while still proving the parameters were
     *      computed and approved by the backend.
     * @param domainSeparator The EIP-712 domain separator (must equal Vault.DOMAIN_SEPARATOR())
     * @param positionId Off-chain position UUID, left-padded into bytes32
     * @param user The user whose position is being closed
     * @param symbol Trading pair, e.g. "BTCUSDT"
     * @param realizedPnl Signed realized PnL in collateral-token decimals
     * @param fee Trading fee charged on this close, in collateral-token decimals
     * @param closedAt Off-chain close timestamp (unix seconds)
     * @param deadline Signature expiration timestamp (unix seconds)
     * @param signature The signature to verify (65 bytes: r + s + v)
     * @param expectedSigner The expected signer (the backend signer address)
     * @return isValid Whether the signature is valid and signed by `expectedSigner`
     */
    function verifyPositionCloseSignature(
        bytes32 domainSeparator,
        bytes32 positionId,
        address user,
        string memory symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        // EIP-712: strings are encoded as their keccak256 hash inside the struct hash.
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionClose(bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 fee,uint256 closedAt,uint256 deadline)"
                ),
                positionId,
                user,
                keccak256(bytes(symbol)),
                realizedPnl,
                fee,
                closedAt,
                deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signer = hash.recover(signature);

        if (signer == address(0)) {
            revert InvalidSigner();
        }

        return signer == expectedSigner;
    }

    /**
     * @notice Verify a reusable close-operator permit signature.
     * @dev The user signs this once to authorize an operator/relayer to submit
     *      multiple future position-close audit records until `expiresAt`.
     */
    function verifyCloseOperatorPermitSignature(
        bytes32 domainSeparator,
        address user,
        address operator,
        uint64 expiresAt,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) internal pure returns (bool) {
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "CloseOperatorPermit(address user,address operator,uint64 expiresAt,uint256 nonce,uint256 deadline)"
                ),
                user,
                operator,
                expiresAt,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signer = hash.recover(signature);

        if (signer == address(0)) {
            revert InvalidSigner();
        }

        return signer == user;
    }

    /**
     * @notice Verify a position-close audit signature that binds a unique closeId.
     * @dev `closeId` is signed by the backend so callers cannot bypass replay
     *      protection by reusing a valid signature with a different id.
     */
    function verifyPositionCloseWithCloseIdSignature(
        bytes32 domainSeparator,
        bytes32 closeId,
        bytes32 positionId,
        address user,
        string calldata symbol,
        int256 realizedPnl,
        uint256 fee,
        uint256 closedAt,
        uint256 deadline,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        if (signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(signature.length);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionClose(bytes32 closeId,bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 fee,uint256 closedAt,uint256 deadline)"
                ),
                closeId,
                positionId,
                user,
                keccak256(bytes(symbol)),
                realizedPnl,
                fee,
                closedAt,
                deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signer = hash.recover(signature);

        if (signer == address(0)) {
            revert InvalidSigner();
        }

        return signer == expectedSigner;
    }

    /**
     * @notice Verify a position-close signature that also authorises the
     *         on-chain balance settlement delta.
     * @dev Used by `recordPositionCloseAndSettleFor` so the AA transaction can
     *      emit the close audit and settle the Vault balance in a single
     *      UserOperation without letting the caller choose an arbitrary PnL
     *      credit/debit.
     */
    function verifyPositionCloseSettlementSignature(
        bytes32 domainSeparator,
        IVault.PositionCloseSettlementParams calldata params,
        address expectedSigner
    ) internal pure returns (bool) {
        if (params.signature.length != SIGNATURE_LENGTH) {
            revert InvalidSignatureLength(params.signature.length);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PositionCloseSettlement(bytes32 closeId,bytes32 positionId,address user,string symbol,int256 realizedPnl,uint256 tradingFee,int256 fundingFee,uint256 borrowingFee,int256 balanceDelta,uint256 closedAt,uint256 deadline)"
                ),
                params.closeId,
                params.positionId,
                params.user,
                keccak256(bytes(params.symbol)),
                params.realizedPnl,
                params.tradingFee,
                params.fundingFee,
                params.borrowingFee,
                params.balanceDelta,
                params.closedAt,
                params.deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signer = hash.recover(params.signature);

        if (signer == address(0)) {
            revert InvalidSigner();
        }

        return signer == expectedSigner;
    }
}
