// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/tokenBank.sol";
import "../src/BaseERC20.sol";

contract TokenBankAutomationTest is Test {
    TokenBank public bank;
    BaseERC20 public token;

    address public owner;
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    address public user3 = address(0x2003);
    address public stranger = address(0x9999);

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 1e18;
    uint256 public constant DEFAULT_THRESHOLD = 10000 * 1e18;

    event AutoSweep(address indexed to, uint256 amount, uint256 timestamp);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    function setUp() public {
        token = new BaseERC20();
        owner = address(this);
        bank = new TokenBank(address(token));

        // 给测试用户转足够的 token（各 30000）
        token.transfer(user1, 30_000 * 1e18);
        token.transfer(user2, 30_000 * 1e18);
        token.transfer(user3, 30_000 * 1e18);
    }

    // ========== 辅助函数 ==========

    function _deposit(address user, uint256 amount) internal {
        vm.prank(user);
        token.approve(address(bank), amount);
        vm.prank(user);
        bank.deposit(amount);
    }

    function _warpToNextInterval() internal {
        vm.warp(block.timestamp + bank.minInterval() + 1);
    }

    // ========== checkUpkeep 测试 ==========

    function test_CheckUpkeep_BelowThreshold() public {
        // 存款未达阈值
        _deposit(user1, 5000 * 1e18); // 5000 < 10000 (threshold)
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);
        assertEq(performData.length, 0); // 不需要时返回空数据
    }

    function test_CheckUpkeep_AboveThreshold() public {
        // 存款超过阈值
        _deposit(user1, 5000 * 1e18);
        _deposit(user2, 6000 * 1e18); // total = 11000 >= 10000
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
        uint256 decodedBalance = abi.decode(performData, (uint256));
        assertEq(decodedBalance, 11000 * 1e18);
    }

    function test_CheckUpkeep_ExactThreshold() public {
        // 存款正好等于阈值
        _deposit(user1, DEFAULT_THRESHOLD);
        _warpToNextInterval();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_CheckUpkeep_MinIntervalNotMet() public {
        // 余额够但间隔未到
        _deposit(user1, DEFAULT_THRESHOLD);
        // 不 warp —— 刚部署 lastUpkeepTime = block.timestamp

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeep_ZeroBalance() public {
        // 余额为 0 时不应触发
        _warpToNextInterval();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    // ========== performUpkeep 测试 ==========

    function test_PerformUpkeep_TransfersHalf() public {
        uint256 depositAmount = 20000 * 1e18;
        _deposit(user1, depositAmount);
        _warpToNextInterval();

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 bankBalanceBefore = token.balanceOf(address(bank));

        // 预期：转移一半 = 10000 * 1e18
        uint256 expectedSweep = bankBalanceBefore / 2;

        vm.expectEmit(true, true, false, true);
        emit AutoSweep(owner, expectedSweep, block.timestamp);

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
        bank.performUpkeep(performData);

        assertEq(token.balanceOf(owner), ownerBalanceBefore + expectedSweep);
        assertEq(token.balanceOf(address(bank)), bankBalanceBefore - expectedSweep);
    }

    function test_PerformUpkeep_ProportionalReduction_SingleUser() public {
        uint256 depositAmount = 20000 * 1e18;
        _deposit(user1, depositAmount);
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        bank.performUpkeep(performData);

        // 一半被转走后，用户余额应变为原来的一半
        assertEq(bank.depositBalances(user1), depositAmount / 2);
        // 用户1 仍能提取剩余余额
        uint256 remainingBalance = bank.depositBalances(user1);
        vm.prank(user1);
        bank.withdraw(remainingBalance);
        assertEq(bank.depositBalances(user1), 0);
    }

    function test_PerformUpkeep_ProportionalReduction_MultipleUsers() public {
        _deposit(user1, 5000 * 1e18);
        _deposit(user2, 10000 * 1e18);
        _deposit(user3, 5000 * 1e18); // total = 20000
        _warpToNextInterval();

        uint256 bal1Before = bank.depositBalances(user1);
        uint256 bal2Before = bank.depositBalances(user2);
        uint256 bal3Before = bank.depositBalances(user3);

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        bank.performUpkeep(performData);

        // 每个用户余额减半（totalBalance=20000, sweep=10000, remaining=10000, ratio=0.5）
        assertEq(bank.depositBalances(user1), bal1Before / 2);
        assertEq(bank.depositBalances(user2), bal2Before / 2);
        assertEq(bank.depositBalances(user3), bal3Before / 2);

        // 验证总额守恒：user balances + owner received = original total
        uint256 usersRemaining = bank.depositBalances(user1)
            + bank.depositBalances(user2)
            + bank.depositBalances(user3);
        uint256 bankRemaining = token.balanceOf(address(bank));
        assertEq(usersRemaining, bankRemaining, "users' records should match bank's actual balance");
    }

    function test_PerformUpkeep_OddBalance() public {
        // 测试奇数余额时整数除法的行为
        uint256 oddAmount = 10001 * 1e18;
        _deposit(user1, oddAmount);
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        bank.performUpkeep(performData);

        uint256 half = oddAmount / 2;
        // bank 剩余 ≈ half (舍入后)
        uint256 bankRemaining = token.balanceOf(address(bank));
        assertApproxEqAbs(bankRemaining, oddAmount - half, 1);
        // 用户余额与 bank 实际余额一致
        assertApproxEqAbs(bank.depositBalances(user1), bankRemaining, 1);
    }

    function test_PerformUpkeep_BelowThresholdReverts() public {
        _deposit(user1, 1000 * 1e18); // well below threshold
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);

        // 即使强行调用也会被 revert
        bytes memory fakeData = abi.encode(uint256(1000 * 1e18));
        vm.expectRevert("TokenBank: below threshold");
        bank.performUpkeep(fakeData);
    }

    function test_PerformUpkeep_MinIntervalNotMetReverts() public {
        _deposit(user1, DEFAULT_THRESHOLD);
        // 不推进时间：lastUpkeepTime == block.timestamp

        bytes memory fakeData = abi.encode(uint256(DEFAULT_THRESHOLD));
        vm.expectRevert("TokenBank: min interval not met");
        bank.performUpkeep(fakeData);
    }

    function test_PerformUpkeep_MismatchedDataReverts() public {
        _deposit(user1, DEFAULT_THRESHOLD);
        _warpToNextInterval();

        // 传入错误的 performData
        bytes memory wrongData = abi.encode(uint256(999999 * 1e18));
        vm.expectRevert("TokenBank: balance mismatch");
        bank.performUpkeep(wrongData);
    }

    function test_PerformUpkeep_CanBeCalledAgain() public {
        // 第一次 sweep
        _deposit(user1, 20000 * 1e18);
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        bank.performUpkeep(performData);
        assertEq(token.balanceOf(address(bank)), 10000 * 1e18);

        // 继续存款，达到阈值后再次 sweep
        _deposit(user2, 10000 * 1e18); // bank now has 20000 again
        _warpToNextInterval();

        (upkeepNeeded, performData) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
        bank.performUpkeep(performData);
        assertEq(token.balanceOf(address(bank)), 10000 * 1e18); // bank: 20000→10000
    }

    // ========== 阈值管理测试 ==========

    function test_SetThreshold() public {
        uint256 newThreshold = 50000 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit ThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);

        bank.setThreshold(newThreshold);
        assertEq(bank.threshold(), newThreshold);
    }

    function test_SetThreshold_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert("TokenBank: only owner");
        bank.setThreshold(50000 * 1e18);
    }

    function test_SetThreshold_ThenCheckUpkeep() public {
        // 提高阈值使当前余额不足
        bank.setThreshold(50000 * 1e18);
        _deposit(user1, 20000 * 1e18); // 20000 < 50000
        _warpToNextInterval();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);

        // 降低阈值
        bank.setThreshold(10000 * 1e18);
        (upkeepNeeded,) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    // ========== 最小间隔管理测试 ==========

    function test_SetMinInterval() public {
        bank.setMinInterval(30 minutes);
        assertEq(bank.minInterval(), 30 minutes);
    }

    function test_SetMinInterval_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert("TokenBank: only owner");
        bank.setMinInterval(30 minutes);
    }

    // ========== depositors 追踪测试 ==========

    function test_DepositorTracking() public {
        assertEq(bank.getDepositorCount(), 0);

        _deposit(user1, 1000 * 1e18);
        assertEq(bank.getDepositorCount(), 1);

        _deposit(user2, 2000 * 1e18);
        assertEq(bank.getDepositorCount(), 2);

        // 同一用户再次存款不重复计数
        _deposit(user1, 500 * 1e18);
        assertEq(bank.getDepositorCount(), 2);
    }

    function test_DepositorTracking_AfterSweep() public {
        _deposit(user1, 10000 * 1e18);
        _deposit(user2, 10000 * 1e18);
        assertEq(bank.getDepositorCount(), 2);
        _warpToNextInterval();

        (bool upkeepNeeded, bytes memory performData) = bank.checkUpkeep("");
        bank.performUpkeep(performData);

        // sweep 后 depositors 数组不变，但余额减半
        assertEq(bank.getDepositorCount(), 2);
        assertEq(bank.depositBalances(user1), 5000 * 1e18);
        assertEq(bank.depositBalances(user2), 5000 * 1e18);
    }

    // ========== 构造函数初始值测试 ==========

    function test_Constructor_InitialValues() public {
        assertEq(bank.owner(), address(this));
        assertEq(bank.threshold(), DEFAULT_THRESHOLD);
        assertEq(bank.minInterval(), 1 hours);
        assertEq(bank.lastUpkeepTime(), block.timestamp);
        assertEq(address(bank.token()), address(token));
    }
}
