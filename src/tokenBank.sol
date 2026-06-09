// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./BaseERC20.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract TokenBank is AutomationCompatible {
    mapping(address => uint256) public depositBalances;
    BaseERC20 public token;

    // ========== Chainlink Automation 状态变量 ==========
    address public owner;               // 接收自动转账的管理员地址
    uint256 public threshold;           // 触发自动转移的存款阈值（可自定义）
    uint256 public lastUpkeepTime;      // 上次执行 upkeep 的时间戳
    uint256 public minInterval;         // 两次 upkeep 之间的最小间隔

    // 记录所有存款用户地址，用于 upkeep 时按比例削减余额
    address[] public depositors;

    // ========== 事件 ==========
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event AutoSweep(address indexed to, uint256 amount, uint256 timestamp);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // ========== 修饰器 ==========
    modifier onlyOwner() {
        require(msg.sender == owner, "TokenBank: only owner");
        _;
    }

    // ========== 构造函数 ==========
    constructor(address _BaseERC20Address) {
        require(_BaseERC20Address != address(0), "TokenBank: address is zero");
        token = BaseERC20(_BaseERC20Address);
        owner = msg.sender;
        threshold = 10000 * 1e18;   // 默认阈值：10000 代币
        minInterval = 1 hours;       // 默认最小间隔：1 小时
        lastUpkeepTime = block.timestamp;
    }

    // ========== 存款 ==========
    function deposit(uint256 amount) external {
        require(amount > 0, "TokenBank: amount is 0");
        require(token.balanceOf(msg.sender) >= amount, "TokenBank: msg.sender insufficient balance");
        require(token.transferFrom(msg.sender, address(this), amount), "TokenBank: deposit failed");

        // 首次存款时，将用户加入 depositors 数组
        if (depositBalances[msg.sender] == 0) {
            depositors.push(msg.sender);
        }
        depositBalances[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }

    // ========== 取款 ==========
    function withdraw(uint256 amount) external {
        require(amount > 0, "TokenBank: amount must be > 0");
        require(depositBalances[msg.sender] >= amount, "TokenBank: amount is invalid");
        depositBalances[msg.sender] -= amount;
        require(token.transfer(msg.sender, amount), "TokenBank: transfer to msg.sender failed");
        emit Withdraw(msg.sender, amount);
    }

    // ========== 查询函数 ==========
    function getTotalBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getDepositBalance(address user) external view returns (uint256) {
        return depositBalances[user];
    }

    function getTokenInfo() external view returns (string memory, string memory, uint8) {
        return (token.name(), token.symbol(), token.decimals());
    }

    function getDepositorCount() external view returns (uint256) {
        return depositors.length;
    }

    // ========== Chainlink Automation 接口实现 ==========

    /**
     * @notice Chainlink Automation 模拟调用，检查是否需要执行 upkeep
     * @dev 此方法仅由 Chainlink 节点通过 eth_call 模拟执行，不会上链
     * @return upkeepNeeded 是否需要执行 performUpkeep
     * @return performData 传给 performUpkeep 的编码数据（当前合约代币总余额）
     */
    function checkUpkeep(bytes calldata /* checkData */)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 totalBalance = token.balanceOf(address(this));
        bool hasEnoughBalance = totalBalance >= threshold;
        bool timePassed = (block.timestamp - lastUpkeepTime) >= minInterval;
        upkeepNeeded = hasEnoughBalance && timePassed && totalBalance > 0;
        if (upkeepNeeded) {
            performData = abi.encode(totalBalance);
        }
        // 不需要 upkeep 时 performData 保持空（节约 gas）
    }

    /**
     * @notice Chainlink Automation 执行函数，将一半存款转移给 owner
     * @dev 任何人可调用，但内部会重新验证条件（防止恶意/竞争调用）
     * @param performData checkUpkeep 返回的编码数据
     */
    function performUpkeep(bytes calldata performData) external override {
        uint256 totalBalance = token.balanceOf(address(this));

        // 验证 performData —— 防御恶意/竞争调用者传入伪造数据
        uint256 expectedBalance = abi.decode(performData, (uint256));
        require(expectedBalance == totalBalance, "TokenBank: balance mismatch");

        // 重新验证条件 —— 防止状态在 checkUpkeep 和 performUpkeep 之间变化
        require(totalBalance >= threshold, "TokenBank: below threshold");
        require((block.timestamp - lastUpkeepTime) >= minInterval, "TokenBank: min interval not met");
        require(totalBalance > 0, "TokenBank: no balance");

        uint256 halfAmount = totalBalance / 2;
        require(halfAmount > 0, "TokenBank: nothing to sweep");

        // 按比例削减所有存款用户的余额
        _reduceDepositsProportionally(halfAmount, totalBalance);

        // 转移一半代币给 owner
        require(token.transfer(owner, halfAmount), "TokenBank: transfer to owner failed");

        lastUpkeepTime = block.timestamp;
        emit AutoSweep(owner, halfAmount, block.timestamp);
    }

    /**
     * @notice 按比例削减所有存款用户的余额
     * @param sweepAmount 要被转走的金额
     * @param totalBalance 削减前的合约总余额
     */
    function _reduceDepositsProportionally(uint256 sweepAmount, uint256 totalBalance) internal {
        uint256 remainingAfterSweep = totalBalance - sweepAmount;
        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            if (depositor != address(0) && depositBalances[depositor] > 0) {
                depositBalances[depositor] =
                    (depositBalances[depositor] * remainingAfterSweep) / totalBalance;
            }
        }
    }

    // ========== 管理员函数 ==========

    /**
     * @notice 设置触发自动转移的存款阈值
     * @param _newThreshold 新阈值（代币最小单位，如 1000 * 1e18 代表 1000 个代币）
     */
    function setThreshold(uint256 _newThreshold) external onlyOwner {
        uint256 old = threshold;
        threshold = _newThreshold;
        emit ThresholdUpdated(old, _newThreshold);
    }

    /**
     * @notice 设置两次 upkeep 之间的最小间隔
     * @param _newInterval 新间隔（秒）
     */
    function setMinInterval(uint256 _newInterval) external onlyOwner {
        minInterval = _newInterval;
    }
}
