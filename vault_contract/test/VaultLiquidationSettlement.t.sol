// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import "../src/contracts/core/vault/Vault.sol";

contract VaultLiquidationSettlementTest is Test {
    Vault internal vault;
    ERC20Mock internal usdc;

    uint256 internal constant BACKEND_KEY = 0xB0BAFEED;
    address internal backendSigner;
    address internal admin = address(0xA11CE);
    address internal referralStorage = address(0xBeef);
    address internal liquidationManager = address(0xA55E7);
    address internal user = address(0xCAFE);
    address internal recipient = address(0xBEEF);

    event LiquidationManagerUpdated(address indexed oldManager, address indexed newManager);
    event LiquidationSettled(
        bytes32 indexed liquidationKey,
        address indexed user,
        address indexed recipient,
        uint256 requestedAmount,
        uint256 debitedAmount,
        bool clearedBalance,
        uint256 invalidatedNonce
    );
    event PositionBalanceSettled(
        bytes32 indexed settlementKey,
        address indexed user,
        int256 balanceDelta,
        uint256 creditedAmount,
        uint256 debitedAmount,
        uint256 newBalance,
        uint256 invalidatedNonce
    );
    event DailySettlementCreditCapUpdated(uint256 oldCap, uint256 newCap);
    event DailyUserSettlementCreditCapUpdated(uint256 oldCap, uint256 newCap);

    function setUp() public {
        vm.chainId(43_113);
        backendSigner = vm.addr(BACKEND_KEY);

        usdc = new ERC20Mock();
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(
            Vault.initialize,
            (Vault.InitParams({
                usdc: address(usdc),
                backendSigner: backendSigner,
                referralStorage: referralStorage,
                domainName: "Primit Vault AVAX Fuji",
                domainVersion: "1.0.0",
                owner: admin,
                plpVault: address(0xDEAD1),
                liquidationManager: address(0xDEAD2),
                protocolFeeRecipient: address(0xDEAD3),
                dailySettlementCreditCap: 0,
                dailyUserSettlementCreditCap: 0
            }))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = Vault(address(proxy));
    }

    function _deposit(address account, uint256 amount) internal {
        usdc.mint(account, amount);
        vm.startPrank(account);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, bytes32(0));
        vm.stopPrank();
    }

    function _signWithdraw(address account, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                account,
                amount,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BACKEND_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _setManager() internal {
        vm.prank(admin);
        vault.setLiquidationManager(liquidationManager);
    }

    function test_ownerSetsLiquidationManager() public {
        // PRI-11: initialize now pre-sets liquidationManager to the setUp mock
        // (address(0xDEAD2)), so rotating to a new address emits the mock as
        // oldManager rather than address(0).
        vm.expectEmit(true, true, false, true, address(vault));
        emit LiquidationManagerUpdated(address(0xDEAD2), liquidationManager);

        _setManager();

        assertEq(vault.liquidationManager(), liquidationManager);
    }

    function test_settleLiquidationClearsBalanceAndInvalidatesPendingWithdrawSignature() public {
        uint256 deposited = 100 ether;
        uint256 withdrawAmount = 10 ether;
        bytes32 liquidationKey = keccak256("bankrupt-liquidation");
        _deposit(user, deposited);
        _setManager();

        uint256 deadline = block.timestamp + 300;
        bytes memory staleWithdrawSig = _signWithdraw(user, withdrawAmount, vault.withdrawNonces(user), deadline);

        vm.expectEmit(true, true, true, true, address(vault));
        emit LiquidationSettled(liquidationKey, user, recipient, 0, deposited, true, 1);

        vm.prank(liquidationManager);
        uint256 debited = vault.settleLiquidation(user, recipient, 0, true, liquidationKey);

        assertEq(debited, deposited);
        assertEq(vault.balances(user), 0);
        assertEq(usdc.balanceOf(recipient), deposited);
        assertEq(vault.withdrawNonces(user), 1);
        assertTrue(vault.usedLiquidationSettlements(liquidationKey));

        vm.expectRevert(Vault.InvalidSignature.selector);
        vm.prank(user);
        vault.withdraw(withdrawAmount, deadline, staleWithdrawSig);
    }

    function test_settleLiquidationDebitsRequestedAmountWhenNotClearing() public {
        uint256 deposited = 100 ether;
        uint256 requested = 35 ether;
        bytes32 liquidationKey = keccak256("partial-liquidation");
        _deposit(user, deposited);
        _setManager();

        vm.prank(liquidationManager);
        uint256 debited = vault.settleLiquidation(user, recipient, requested, false, liquidationKey);

        assertEq(debited, requested);
        assertEq(vault.balances(user), deposited - requested);
        assertEq(usdc.balanceOf(recipient), requested);
        assertEq(vault.withdrawNonces(user), 1);
    }

    function test_settleLiquidationAllowsZeroDebitForNonceInvalidation() public {
        uint256 deposited = 100 ether;
        bytes32 liquidationKey = keccak256("zero-debit-liquidation");
        _deposit(user, deposited);
        _setManager();

        vm.expectEmit(true, true, true, true, address(vault));
        emit LiquidationSettled(liquidationKey, user, recipient, 0, 0, false, 1);

        vm.prank(liquidationManager);
        uint256 debited = vault.settleLiquidation(user, recipient, 0, false, liquidationKey);

        assertEq(debited, 0);
        assertEq(vault.balances(user), deposited);
        assertEq(usdc.balanceOf(recipient), 0);
        assertEq(vault.withdrawNonces(user), 1);
        assertTrue(vault.usedLiquidationSettlements(liquidationKey));
    }

    function test_settleLiquidationCannotOverdrawUserBalance() public {
        uint256 deposited = 50 ether;
        bytes32 liquidationKey = keccak256("overdraw-liquidation");
        _deposit(user, deposited);
        _setManager();

        vm.prank(liquidationManager);
        uint256 debited = vault.settleLiquidation(user, recipient, 100 ether, false, liquidationKey);

        assertEq(debited, deposited);
        assertEq(vault.balances(user), 0);
        assertEq(usdc.balanceOf(recipient), deposited);
    }

    function test_revertsWhenCallerIsNotLiquidationManager() public {
        _deposit(user, 10 ether);
        _setManager();

        vm.expectRevert(abi.encodeWithSelector(Vault.UnauthorizedLiquidationManager.selector, address(this)));
        vault.settleLiquidation(user, recipient, 1 ether, false, keccak256("unauthorized"));
    }

    function test_revertsWhenLiquidationKeyIsReused() public {
        bytes32 liquidationKey = keccak256("reused-liquidation");
        _deposit(user, 10 ether);
        _setManager();

        vm.prank(liquidationManager);
        vault.settleLiquidation(user, recipient, 1 ether, false, liquidationKey);

        vm.expectRevert(abi.encodeWithSelector(Vault.LiquidationAlreadySettled.selector, liquidationKey));
        vm.prank(liquidationManager);
        vault.settleLiquidation(user, recipient, 1 ether, false, liquidationKey);
    }

    function test_settlePositionBalanceCreditsProfitWhenUserChainBalanceIsZero() public {
        bytes32 settlementKey = keccak256("profit-close");
        vm.prank(admin);
        vault.setDailySettlementCreditCap(10 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(10 ether);

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionBalanceSettled(settlementKey, user, 10 ether, 10 ether, 0, 10 ether, 1);

        vm.prank(backendSigner);
        (uint256 credited, uint256 debited) = vault.settlePositionBalance(user, 10 ether, settlementKey);

        assertEq(credited, 10 ether);
        assertEq(debited, 0);
        assertEq(vault.balances(user), 10 ether);
        assertEq(vault.withdrawNonces(user), 1);
        assertEq(vault.totalPositionSettlementCredits(), 10 ether);
        assertTrue(vault.usedPositionBalanceSettlements(settlementKey));
    }

    function test_settlePositionBalanceLossKeepsZeroBalanceAtZero() public {
        bytes32 settlementKey = keccak256("loss-close-zero");

        vm.expectEmit(true, true, false, true, address(vault));
        emit PositionBalanceSettled(settlementKey, user, -10 ether, 0, 0, 0, 1);

        vm.prank(backendSigner);
        (uint256 credited, uint256 debited) = vault.settlePositionBalance(user, -10 ether, settlementKey);

        assertEq(credited, 0);
        assertEq(debited, 0);
        assertEq(vault.balances(user), 0);
        assertEq(vault.withdrawNonces(user), 1);
        assertEq(vault.totalPositionSettlementDebits(), 0);
    }

    function test_settlePositionBalanceLossDebitsOnlyAvailableChainBalance() public {
        bytes32 settlementKey = keccak256("loss-close-partial");
        _deposit(user, 6 ether);
        _setManager();

        vm.prank(liquidationManager);
        (uint256 credited, uint256 debited) = vault.settlePositionBalance(user, -10 ether, settlementKey);

        assertEq(credited, 0);
        assertEq(debited, 6 ether);
        assertEq(vault.balances(user), 0);
        assertEq(vault.totalPositionSettlementDebits(), 6 ether);
    }

    function test_revertsWhenPositionBalanceSettlementKeyIsReused() public {
        bytes32 settlementKey = keccak256("reused-position-balance");
        _setManager();
        vm.prank(admin);
        vault.setDailySettlementCreditCap(2 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(2 ether);

        vm.prank(liquidationManager);
        vault.settlePositionBalance(user, 1 ether, settlementKey);

        vm.expectRevert(abi.encodeWithSelector(Vault.PositionBalanceSettlementAlreadyUsed.selector, settlementKey));
        vm.prank(liquidationManager);
        vault.settlePositionBalance(user, 1 ether, settlementKey);
    }

    function test_ownerSetsDailySettlementCreditCap() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit DailySettlementCreditCapUpdated(0, 100 ether);

        vm.prank(admin);
        vault.setDailySettlementCreditCap(100 ether);

        assertEq(vault.dailySettlementCreditCap(), 100 ether);
    }

    function test_ownerSetsDailyUserSettlementCreditCap() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit DailyUserSettlementCreditCapUpdated(0, 10 ether);

        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(10 ether);

        assertEq(vault.dailyUserSettlementCreditCap(), 10 ether);
    }

    function test_revertsWhenPositiveSettlementCreditCapExceeded() public {
        bytes32 settlementKey = keccak256("cap-exceeded");
        vm.prank(admin);
        vault.setDailySettlementCreditCap(9 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(20 ether);

        vm.expectRevert(abi.encodeWithSelector(Vault.DailySettlementCreditCapExceeded.selector, 10 ether, 9 ether));
        vm.prank(backendSigner);
        vault.settlePositionBalance(user, 10 ether, settlementKey);
    }

    function test_revertsWhenPositiveSettlementUserCreditCapExceeded() public {
        bytes32 settlementKey = keccak256("user-cap-exceeded");
        vm.prank(admin);
        vault.setDailySettlementCreditCap(20 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(9 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Vault.DailyUserSettlementCreditCapExceeded.selector, user, 10 ether, 9 ether)
        );
        vm.prank(backendSigner);
        vault.settlePositionBalance(user, 10 ether, settlementKey);
    }

    function test_positiveSettlementTracksGlobalAndPerUserDailyCredit() public {
        address secondUser = address(0xC0FFEE);
        vm.prank(admin);
        vault.setDailySettlementCreditCap(15 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(10 ether);

        vm.prank(backendSigner);
        vault.settlePositionBalance(user, 10 ether, keccak256("user-one"));
        vm.prank(backendSigner);
        vault.settlePositionBalance(secondUser, 5 ether, keccak256("user-two"));

        assertEq(vault.settlementCreditUsedAmount(), 15 ether);
        assertEq(vault.userSettlementCreditUsedAmount(user), 10 ether);
        assertEq(vault.userSettlementCreditUsedAmount(secondUser), 5 ether);

        vm.expectRevert(abi.encodeWithSelector(Vault.DailySettlementCreditCapExceeded.selector, 1 ether, 0));
        vm.prank(backendSigner);
        vault.settlePositionBalance(secondUser, 1 ether, keccak256("global-exhausted"));
    }

    function test_reinitializeSettlementCapsSetsCapsAtomically() public {
        Vault impl = new Vault();
        bytes memory initData = abi.encodeCall(Vault.reinitializeSettlementCaps, (100 ether, 10 ether));
        vm.prank(admin);
        vault.upgradeToAndCall(address(impl), initData);

        assertEq(vault.dailySettlementCreditCap(), 100 ether);
        assertEq(vault.dailyUserSettlementCreditCap(), 10 ether);
    }

    function test_settlePositionBalanceFromBackendSignerCallerSucceeds() public {
        bytes32 settlementKey = keccak256("backend-caller");
        vm.prank(admin);
        vault.setDailySettlementCreditCap(3 ether);
        vm.prank(admin);
        vault.setDailyUserSettlementCreditCap(3 ether);

        vm.prank(backendSigner);
        (uint256 credited, uint256 debited) = vault.settlePositionBalance(user, 3 ether, settlementKey);

        assertEq(credited, 3 ether);
        assertEq(debited, 0);
        assertEq(vault.balances(user), 3 ether);
    }
}
