# TokenBank Demo

Solidity 智能合约学习项目，包含 ERC20、ERC721 自实现、代币银行、ETH 银行及配套前端 DApp。

## 合约文件

### `src/BaseERC20.sol` — ERC20 代币（自实现）

不依赖 OpenZeppelin，从零实现的 ERC20 代币合约。

| 功能 | 说明 |
|------|------|
| `transfer` | 转账代币 |
| `transferFrom` | 授权转账（需先 approve） |
| `approve` / `allowance` | 授权机制 |
| `transferWithCallback` | 带回调的转账（类似 ERC1363），接收方为合约时触发 `tokensReceived` |
| `balanceOf` | 查询余额 |

- 初始供应量: 1 亿 (100,000,000) 枚
- 小数位: 18
- 名称/符号: BaseERC20 / BERC20

### `src/myToken.sol` — ERC20 代币（OpenZeppelin 版）

基于 OpenZeppelin ERC20 的标准代币，用于测试对比。

- 初始供应: 100 亿 (1e10) 枚
- 构造函数参数: name\_, symbol\_
- 部署时全部铸造给部署者

### `src/tokenBank.sol` — 代币银行

存入/取出 BaseERC20 代币的银行合约。

| 方法 | 说明 |
|------|------|
| `deposit(amount)` | 存入代币（需先 approve） |
| `withdraw(amount)` | 取出存款 |
| `getDepositBalance(user)` | 查询用户存款余额 |
| `getTotalBalance()` | 查询银行总存款 |
| `getTokenInfo()` | 获取代币名称、符号、小数位 |

**流程**: 用户先调用 BaseERC20 的 `approve` 授权银行 → 再调用 `deposit` 存款 → 随时 `withdraw` 取出。

### `src/BankDemo.sol` — ETH 银行 + Top3 排行

接收和提取 ETH 的银行合约，带存款排行榜。

| 功能 | 说明 |
|------|------|
| `deposit()` | 存入 ETH（或直接转账触发 `receive`） |
| `withdraw()` | 管理员提取全部 ETH |
| `getTopDepositors()` | 获取存款 Top 3 地址 |
| `getTopDepositAmounts()` | 获取 Top 3 存款金额 |
| `getDepositorBalance(addr)` | 查询指定地址存款 |
| `updateTopDepositors(addr)` | 内部维护降序排行榜 |

### `src/ERC721Demo.sol` — ERC721 NFT（自实现）

不依赖 OpenZeppelin，从零实现的 ERC721 非同质化代币合约。

| 功能 | 说明 |
|------|------|
| `mint(to, tokenId)` | 铸造 NFT |
| `transferFrom` / `safeTransferFrom` | 转账/安全转账 |
| `approve` / `setApprovalForAll` | 单个授权 / 全部授权 |
| `tokenURI` | 返回 `baseURI + tokenId` 的元数据地址 |
| `supportsInterface` | ERC165 接口检测 |
| `BaseERC721Receiver` | ERC721 接收器实现示例 |

## 测试

| 测试文件 | 测试内容 | 用例数 |
|----------|----------|--------|
| `test/TokenBank.t.sol` | TokenBank 存款/取款/查询 | 14 |
| `test/TokenBankUSDT.t.sol` | USDT 分叉测试（transferFrom 无返回值兼容） | 7 |
| `test/BankDemo.t.sol` | ETH 银行存款/取款/Top3 排行 | 16 |
| `test/ERC721Demo.t.sol` | ERC721 铸造/转账/授权/URI | 30 |

运行测试:

```bash
forge test
```

## 前端 (frontend/)

React + TypeScript + wagmi 构建的 TokenBank DApp，详见 [frontend/README.md](frontend/README.md)。

## 快速开始

```bash
# 安装依赖
forge install

# 编译
forge build

# 运行测试
forge test

# 启动本地链
anvil --port 8545

# 部署合约到本地
forge script script/DeployTokenBank.s.sol:DeployTokenBank \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 启动前端
cd frontend && npm install && npm run dev
```
