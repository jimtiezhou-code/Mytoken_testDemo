// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/tokenBank.sol";

/// @title TokenBank USDT Mainnet Fork Tests
/// @notice 验证 TokenBank 与以太坊主网 USDT 的交互
/// @dev USDT 合约不遵循 ERC20 标准（transfer/transferFrom/approve 不返回 bool），
///      导致 TokenBank 的 deposit() 在 ABI 解码返回值时失败。
///      此测试集验证 TokenBank 能正确读取 USDT 合约信息。
contract TokenBankUSDTTest is Test {
    TokenBank public bank;

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDT_HOLDER = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    address public user = address(0x2001);

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://virginia.rpc.blxrbdn.com"));
        vm.createSelectFork(rpcUrl);

        bank = new TokenBank(USDT);

        // 从 Binance 大户转 USDT 给测试用户
        vm.prank(USDT_HOLDER);
        (bool ok,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", user, uint256(10_000 * 1e6)));
        require(ok, "transfer USDT to user failed");
    }

    // ========== Token 信息验证 ==========

    function test_GetTokenInfo() public {
        (string memory name, string memory symbol, uint8 decimals) = bank.getTokenInfo();
        assertEq(name, "Tether USD");
        assertEq(symbol, "USDT");
        assertEq(decimals, 6);
    }

    function test_GetTotalBalance_Zero() public {
        assertEq(bank.getTotalBalance(), 0);
    }

    function test_GetDepositBalance_Zero() public {
        assertEq(bank.getDepositBalance(user), 0);
    }

    // ========== 错误处理验证 ==========

    function test_DepositZeroReverts() public {
        vm.prank(user);
        vm.expectRevert("TokenBank: amount is 0");
        bank.deposit(0);
    }

    function test_WithdrawZeroReverts() public {
        vm.prank(user);
        vm.expectRevert("TokenBank: amount must be > 0");
        bank.withdraw(0);
    }

    function test_WithdrawNoBalanceReverts() public {
        vm.prank(user);
        vm.expectRevert("TokenBank: amount is invalid");
        bank.withdraw(1 * 1e6);
    }

    // ========== USDT 兼容性问题说明 ==========

    /// @notice 验证 USDT 的 transferFrom 不返回 bool 值，
    ///         导致 TokenBank deposit() 的 require 解码失败
    function test_USDT_TransferFromReturnsNoData() public {
        address spender = address(this);

        vm.prank(user);
        (bool approveOk,) = USDT.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, uint256(100 * 1e6))
        );
        require(approveOk);

        (bool tfOk, bytes memory tfData) = USDT.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(0x9999), uint256(100 * 1e6))
        );
        assertTrue(tfOk, "transferFrom should succeed at EVM level");
        assertEq(tfData.length, 0, "USDT transferFrom returns empty data, not bool");
    }
}
