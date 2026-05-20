
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./BaseERC20.sol";


contract TokenBank {
    mapping(address => uint256) public depositBalances;
    BaseERC20 public token;

    constructor(address _BaseERC20Address) {
        require(_BaseERC20Address != address(0), "TokenBank: address is zero");
        token = BaseERC20(_BaseERC20Address);
    }

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);

    function deposit(uint256 amount) external {
        require(amount > 0, "TokenBank: amount is 0");
        require(token.balanceOf(msg.sender) >= amount, "TokenBank: msg.sender insufficient balance");
        require(token.transferFrom(msg.sender, address(this), amount), "TokenBank: deposit failed");
        depositBalances[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "TokenBank: amount must be > 0");
        require(depositBalances[msg.sender] >= amount, "TokenBank: amount is invalid");
        depositBalances[msg.sender] -= amount;
        require(token.transfer(msg.sender, amount), "TokenBank: transfer to msg.sender failed");
        emit Withdraw(msg.sender, amount);

    }

    function getTotalBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
    //查询用户自己的存款余额
    function getDepositBalance(address user) external view returns (uint256) {
        return depositBalances[user];
    }

    //返回银行的token信息

    function getTokenInfo() external view returns (string memory, string memory, uint8) {
        return (token.name(),token.symbol(), token.decimals());
    }




}

