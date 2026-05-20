// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/tokenBank.sol";
import "../src/BaseERC20.sol";

contract TokenBankTest is Test {
    TokenBank public bank;
    BaseERC20 public token;

    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 1e18;

    function setUp() public {
        token = new BaseERC20();
        bank = new TokenBank(address(token));

        // 给测试用户转 token
        vm.prank(address(this));
        token.transfer(user1, 10_000 * 1e18);
        vm.prank(address(this));
        token.transfer(user2, 10_000 * 1e18);
    }

    // ========== 存款测试 ==========

    function test_Deposit() public {
        uint256 amount = 1000 * 1e18;

        uint256 bankBalanceBefore = token.balanceOf(address(bank));
        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 userDepositBefore = bank.depositBalances(user1);

        vm.prank(user1);
        token.approve(address(bank), amount);
        vm.prank(user1);
        bank.deposit(amount);

        assertEq(bank.depositBalances(user1), userDepositBefore + amount);
        assertEq(token.balanceOf(address(bank)), bankBalanceBefore + amount);
        assertEq(token.balanceOf(user1), userBalanceBefore - amount);
    }

    function test_MultipleDepositsAccumulate() public {
        vm.prank(user1);
        token.approve(address(bank), 3000 * 1e18);

        vm.prank(user1);
        bank.deposit(1000 * 1e18);
        vm.prank(user1);
        bank.deposit(2000 * 1e18);

        assertEq(bank.depositBalances(user1), 3000 * 1e18);
        assertEq(token.balanceOf(address(bank)), 3000 * 1e18);
    }

    function test_MultipleUsersDeposit() public {
        vm.prank(user1);
        token.approve(address(bank), 1000 * 1e18);
        vm.prank(user1);
        bank.deposit(1000 * 1e18);

        vm.prank(user2);
        token.approve(address(bank), 2000 * 1e18);
        vm.prank(user2);
        bank.deposit(2000 * 1e18);

        assertEq(bank.depositBalances(user1), 1000 * 1e18);
        assertEq(bank.depositBalances(user2), 2000 * 1e18);
        assertEq(token.balanceOf(address(bank)), 3000 * 1e18);
    }

    // ========== 取款测试 ==========

    function test_Withdraw() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 withdrawAmount = 300 * 1e18;

        vm.prank(user1);
        token.approve(address(bank), depositAmount);
        vm.prank(user1);
        bank.deposit(depositAmount);

        uint256 bankBalanceBefore = token.balanceOf(address(bank));
        uint256 userBalanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        bank.withdraw(withdrawAmount);

        assertEq(bank.depositBalances(user1), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(address(bank)), bankBalanceBefore - withdrawAmount);
        assertEq(token.balanceOf(user1), userBalanceBefore + withdrawAmount);
    }

    function test_FullDepositAndWithdraw() public {
        uint256 amount = 5000 * 1e18;

        vm.prank(user1);
        token.approve(address(bank), amount);
        vm.prank(user1);
        bank.deposit(amount);

        assertEq(bank.depositBalances(user1), amount);
        assertEq(token.balanceOf(address(bank)), amount);

        vm.prank(user1);
        bank.withdraw(amount);

        assertEq(bank.depositBalances(user1), 0);
        assertEq(token.balanceOf(address(bank)), 0);
    }

    function test_WithdrawOverBalanceReverts() public {
        vm.prank(user1);
        token.approve(address(bank), 100 * 1e18);
        vm.prank(user1);
        bank.deposit(100 * 1e18);

        vm.prank(user1);
        vm.expectRevert("TokenBank: amount is invalid");
        bank.withdraw(200 * 1e18);
    }

    // ========== 查询测试 ==========

    function test_GetTotalBalance() public {
        vm.prank(user1);
        token.approve(address(bank), 1500 * 1e18);
        vm.prank(user1);
        bank.deposit(1500 * 1e18);

        assertEq(bank.getTotalBalance(), 1500 * 1e18);
    }

    function test_GetDepositBalance() public {
        vm.prank(user1);
        token.approve(address(bank), 2500 * 1e18);
        vm.prank(user1);
        bank.deposit(2500 * 1e18);

        assertEq(bank.getDepositBalance(user1), 2500 * 1e18);
        assertEq(bank.getDepositBalance(user2), 0);
    }

    function test_GetTokenInfo() public {
        (string memory name, string memory symbol, uint8 decimals) = bank.getTokenInfo();
        assertEq(name, "BaseERC20");
        assertEq(symbol, "BERC20");
        assertEq(decimals, 18);
    }

    // ========== 错误处理测试 ==========

    function test_DepositZeroReverts() public {
        vm.prank(user1);
        vm.expectRevert("TokenBank: amount is 0");
        bank.deposit(0);
    }

    function test_WithdrawZeroReverts() public {
        vm.prank(user1);
        vm.expectRevert("TokenBank: amount must be > 0");
        bank.withdraw(0);
    }

    function test_WithdrawNoDepositReverts() public {
        vm.prank(user1);
        vm.expectRevert("TokenBank: amount is invalid");
        bank.withdraw(1 * 1e18);
    }

    function test_DepositWithoutApprovalReverts() public {
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        bank.deposit(100 * 1e18);
    }

    function test_DepositInsufficientBalanceReverts() public {
        // 用户余额 10000, 但尝试存 20000
        vm.prank(user1);
        token.approve(address(bank), 20000 * 1e18);
        vm.prank(user1);
        vm.expectRevert("TokenBank: msg.sender insufficient balance");
        bank.deposit(20000 * 1e18);
    }
}
