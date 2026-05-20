// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BankDemo.sol";

contract BankDemoTest is Test {
    BankDemo public bank;

    address public admin = address(0x1000);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    address public user3 = address(0x2003);
    address public user4 = address(0x2004);

    function setUp() public {
        vm.prank(admin);
        bank = new BankDemo();
        // 给测试用户转入 ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);
    }

    // ========== 1. 存款前后余额检查 ==========

    function test_DepositUpdatesBalance() public {
        uint256 amount = 1 ether;

        uint256 balanceBefore = bank.balances(user1);
        assertEq(balanceBefore, 0, "Balance before deposit should be 0");

        vm.prank(user1);
        bank.deposit{value: amount}();

        uint256 balanceAfter = bank.balances(user1);
        assertEq(balanceAfter, amount, "Balance after deposit should match amount");
    }

    function test_MultipleDepositsFromSameUser() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user1);
        bank.deposit{value: 2 ether}();

        uint256 balance = bank.balances(user1);
        assertEq(balance, 3 ether, "Multiple deposits should accumulate");
    }

    function test_DepositViaReceive() public {
        uint256 amount = 0.5 ether;

        vm.prank(user1);
        (bool success, ) = address(bank).call{value: amount}("");
        assertTrue(success);

        assertEq(bank.balances(user1), amount, "Balance after receive() should match");
    }

    function test_DepositZeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be > 0");
        bank.deposit{value: 0}();
    }

    // ========== 2. Top3 排行榜检查 ==========

    function test_Top3_OneUser() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        assertEq(depositors[0], user1, "Top1 should be user1");
        assertEq(amounts[0], 1 ether, "Top1 amount should be 1 ether");
        assertEq(depositors[1], address(0), "Top2 should be empty");
        assertEq(depositors[2], address(0), "Top3 should be empty");
    }

    function test_Top3_TwoUsers() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user2);
        bank.deposit{value: 2 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        assertEq(depositors[0], user2, "Top1 should be user2 (2 ether)");
        assertEq(amounts[0], 2 ether);
        assertEq(depositors[1], user1, "Top2 should be user1 (1 ether)");
        assertEq(amounts[1], 1 ether);
        assertEq(depositors[2], address(0), "Top3 should be empty");
    }

    function test_Top3_ThreeUsers() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user2);
        bank.deposit{value: 3 ether}();
        vm.prank(user3);
        bank.deposit{value: 2 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        assertEq(depositors[0], user2, "Top1 should be user2 (3 ether)");
        assertEq(amounts[0], 3 ether);
        assertEq(depositors[1], user3, "Top2 should be user3 (2 ether)");
        assertEq(amounts[1], 2 ether);
        assertEq(depositors[2], user1, "Top3 should be user1 (1 ether)");
        assertEq(amounts[2], 1 ether);
    }

    function test_Top3_FourUsers() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user2);
        bank.deposit{value: 4 ether}();
        vm.prank(user3);
        bank.deposit{value: 2 ether}();
        vm.prank(user4);
        bank.deposit{value: 3 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        // Top3: user2(4), user4(3), user3(2), user1(1) 被挤出
        assertEq(depositors[0], user2, "Top1 should be user2 (4 ether)");
        assertEq(amounts[0], 4 ether);
        assertEq(depositors[1], user4, "Top2 should be user4 (3 ether)");
        assertEq(amounts[1], 3 ether);
        assertEq(depositors[2], user3, "Top3 should be user3 (2 ether)");
        assertEq(amounts[2], 2 ether);
    }

    function test_Top3_SameUserMultipleDeposits() public {
        // user1 第一次存款排第一
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        // user2 存款超过 user1
        vm.prank(user2);
        bank.deposit{value: 2 ether}();
        // user1 再次存款，总额 3 ether，应排第一
        vm.prank(user1);
        bank.deposit{value: 2 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        assertEq(depositors[0], user1, "Top1 should be user1 after second deposit (3 ether total)");
        assertEq(amounts[0], 3 ether);
        assertEq(depositors[1], user2, "Top2 should be user2 (2 ether)");
        assertEq(amounts[1], 2 ether);
        assertEq(depositors[2], address(0), "Top3 should be empty");
    }

    function test_Top3_SameUserDepositsWithFourUsers() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user2);
        bank.deposit{value: 2 ether}();
        vm.prank(user3);
        bank.deposit{value: 3 ether}();
        vm.prank(user4);
        bank.deposit{value: 4 ether}();

        // user1 追加存款，总额变 5 ether，应排第一
        vm.prank(user1);
        bank.deposit{value: 4 ether}();

        (address[3] memory depositors, uint256[3] memory amounts) = _getTop3();
        assertEq(depositors[0], user1, "Top1 should be user1 (5 ether)");
        assertEq(amounts[0], 5 ether);
        assertEq(depositors[1], user4, "Top2 should be user4 (4 ether)");
        assertEq(amounts[1], 4 ether);
        assertEq(depositors[2], user3, "Top3 should be user3 (3 ether)");
        assertEq(amounts[2], 3 ether);
    }

    // ========== 3. 仅管理员可取款 ==========

    function test_OnlyOwnerCanWithdraw() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();

        // 非管理员取款应失败
        vm.prank(user1);
        vm.expectRevert("Not owner");
        bank.withdraw();
    }

    function test_OwnerWithdrawSuccess() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user2);
        bank.deposit{value: 2 ether}();

        uint256 contractBalance = address(bank).balance;
        assertEq(contractBalance, 3 ether);

        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        bank.withdraw();

        assertEq(address(bank).balance, 0, "Contract balance should be 0 after withdraw");
        assertEq(admin.balance, adminBalanceBefore + 3 ether, "Admin should receive all funds");
    }

    function test_WithdrawWithZeroBalanceReverts() public {
        vm.prank(admin);
        vm.expectRevert("No balance to withdraw");
        bank.withdraw();
    }

    function test_GetTopDepositorsAndAmounts() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();

        address[3] memory depositors = bank.getTopDepositors();
        uint256[3] memory amounts = bank.getTopDepositAmounts();

        assertEq(depositors[0], user1);
        assertEq(amounts[0], 1 ether);
    }

    function test_GetTotalBalance() public {
        vm.prank(user1);
        bank.deposit{value: 1.5 ether}();
        vm.prank(user2);
        bank.deposit{value: 2.5 ether}();

        assertEq(bank.getTotalBalance(), 4 ether);
    }

    function test_GetDepositorBalance() public {
        vm.prank(user1);
        bank.deposit{value: 3.14 ether}();

        assertEq(bank.getDepositorBalance(user1), 3.14 ether);
        assertEq(bank.getDepositorBalance(user2), 0);
    }

    // ========== 辅助函数 ==========

    function _getTop3() internal view returns (address[3] memory, uint256[3] memory) {
        return (bank.getTopDepositors(), bank.getTopDepositAmounts());
    }
}
