// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBank {
    function deposit() external payable;
    function withdraw() external;
}

contract BankDemo is IBank {
    // 使用映射记录每个用户的存款数据
    mapping(address => uint256) public balances;
    // 使用数组记录前三名存款地址
    address[3] public topDepositors;
    // 管理员地址
    address public owner;

    // 存款事件
    event Deposit(address indexed depositor, uint256 amount);
    // 提款事件
    event Withdraw(address indexed admin, uint256 amount);

    // 构造函数，初始化管理员
    constructor() {
        owner = msg.sender;
    }

    // 修改器：仅管理员可调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // 接收ETH转账时自动触发存款
    receive() external payable virtual {
        deposit();
    }

    // 显式存款函数
    function deposit() public payable virtual override {
        require(msg.value > 0, "Amount must be > 0");
        balances[msg.sender] += msg.value;
        updateTopDepositors(msg.sender);
        emit Deposit(msg.sender, msg.value);
    }

    // 更新前三名排行
    function updateTopDepositors(address depositor) internal {
        uint256 newBalance = balances[depositor];

        // 先从数组中移除该地址（如果已存在）
        for (uint256 i = 0; i < 3; i++) {
            if (topDepositors[i] == depositor) {
                // 将后面的元素前移
                for (uint256 j = i; j < 2; j++) {
                    topDepositors[j] = topDepositors[j + 1];
                }
                topDepositors[2] = address(0);
                break;
            }
        }

        // 按余额降序插入到正确位置
        for (uint256 i = 0; i < 3; i++) {
            if (newBalance > balances[topDepositors[i]]) {
                // 将当前位置及之后的元素后移
                for (uint256 j = 2; j > i; j--) {
                    topDepositors[j] = topDepositors[j - 1];
                }
                topDepositors[i] = depositor;
                break;
            }
        }
    }

    // 管理员提取所有ETH
    function withdraw() external virtual override onlyOwner {
        uint256 totalBalance = address(this).balance;
        require(totalBalance > 0, "No balance to withdraw");
        //1、执行转账，捕获结果
        (bool success, ) = payable(owner).call{value: totalBalance}("");
        //2、判断转账是否成功，如果失败，则抛出异常
        require(success, "Withdraw failed");
        emit Withdraw(owner, totalBalance);
    }
    

    // 获取当前合约ETH总余额
    function getTotalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // 查询指定地址的存款余额
    function getDepositorBalance(address depositor) external view returns (uint256) {
        return balances[depositor];
    }

    // 获取Top3存款地址
    function getTopDepositors() external view returns (address[3] memory) {
        return topDepositors;
    }

    // 获取Top3存款金额
    function getTopDepositAmounts() external view returns (uint256[3] memory) {
        uint256[3] memory amounts;
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = balances[topDepositors[i]];
        }
        return amounts;
    }
}
