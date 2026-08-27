// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./Role.sol";

/// @title RoleStore
/// @notice Stores roles and their members.
/// @dev Adapted from gmx-synthetics/contracts/role/RoleStore.sol.
///      Single source of truth for permissions across all Primit AVAX contracts.
contract RoleStore {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    /// @notice The set of all role identifiers (Role.ADMIN, Role.LIQUIDATION_KEEPER, …)
    EnumerableSet.Bytes32Set internal _roles;

    /// @notice For each role, the set of addresses that hold the role
    mapping(bytes32 => EnumerableSet.AddressSet) internal _roleMembers;

    /// @notice For each account, the set of roles it holds (gas-optimized reverse lookup)
    mapping(address => EnumerableSet.Bytes32Set) internal _accountRoles;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error Unauthorized(address account, bytes32 role);
    error ZeroAddress();
    error InvalidRole(bytes32 role);

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed by);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed by);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyAdmin() {
        if (!_hasRole(msg.sender, Role.ADMIN)) revert Unauthorized(msg.sender, Role.ADMIN);
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /// @param initialAdmin First admin address. MUST be a Safe multisig, NOT an EOA.
    ///                     See DR-2026-0506-001 §3.3.
    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert ZeroAddress();
        _grantRole(Role.ADMIN, initialAdmin);
    }

    // -----------------------------------------------------------------------
    // Admin functions
    // -----------------------------------------------------------------------

    function grantRole(bytes32 role, address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == bytes32(0)) revert InvalidRole(role);
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        _revokeRole(role, account);
    }

    // -----------------------------------------------------------------------
    // View functions
    // -----------------------------------------------------------------------

    function hasRole(address account, bytes32 role) external view returns (bool) {
        return _hasRole(account, role);
    }

    function getRoleMembers(bytes32 role, uint256 start, uint256 end) external view returns (address[] memory) {
        EnumerableSet.AddressSet storage members = _roleMembers[role];
        uint256 length = members.length();
        if (end > length) end = length;
        if (start >= end) return new address[](0);
        address[] memory out = new address[](end - start);
        for (uint256 i = start; i < end; i++) out[i - start] = members.at(i);
        return out;
    }

    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return _roleMembers[role].length();
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _hasRole(address account, bytes32 role) internal view returns (bool) {
        return _roleMembers[role].contains(account);
    }

    function _grantRole(bytes32 role, address account) internal {
        _roles.add(role);
        if (_roleMembers[role].add(account)) {
            _accountRoles[account].add(role);
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (_roleMembers[role].remove(account)) {
            _accountRoles[account].remove(role);
            emit RoleRevoked(role, account, msg.sender);
            // CertiK PRI-19 · prune the role from _roles when its last member is revoked,
            // so _roles reflects the currently-active roles and never accumulates entries
            // for empty sets. Any future logic that iterates _roles now sees only real,
            // in-use roles.
            if (_roleMembers[role].length() == 0) {
                _roles.remove(role);
            }
        }
    }
}
