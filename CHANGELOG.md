# 更新日志

## 2026-05-26 — 后端转账索引 + SIWE登录 + 转账记录查询

### 新增功能

#### 1. 后端服务 (backend/)

基于 Express.js + SQLite3 + viem 构建的后端服务，提供以下功能：

- **SQLite3 数据库** — 使用 better-sqlite3 创建本地数据库 `tokenbank.db`，存储 ERC20 代币转账事件
- **转账事件索引器** — 启动时同步历史 Transfer 事件，并实时监听新区块中的转账事件，自动写入数据库
- **RESTful API**
  - `GET /api/transfers/:address` — 根据钱包地址查询其所有转入/转出记录（支持分页）
  - `GET /api/transfers` — 查询全部转账记录（支持分页）
  - `GET /health` — 健康检查接口

后端运行在 `http://localhost:3001`。

#### 2. 前端 SIWE 登录

- 用户连接钱包后，需点击「登录」按钮进行 SIWE（Sign-In with Ethereum）签名认证
- 使用 wagmi 的 `useSignMessage` 进行消息签名，验证用户对地址的所有权
- 签名成功后，前端会自动获取该地址的转账记录

#### 3. 转账记录展示

- SIWE 登录成功后，在操作卡片下方展示「转账记录」面板
- 显示内容：交易哈希、区块号、发送方、接收方、金额（含正负标识）
- 转入金额显示为绿色（+），转出金额显示为红色（-）
- 当前用户地址在表格中标记为「自己」
- 支持手动刷新按钮

### 技术实现

| 组件 | 技术栈 |
|------|--------|
| 后端框架 | Express.js + TypeScript |
| 数据库 | SQLite3 (better-sqlite3) |
| 链交互 | viem (PublicClient + watchEvent) |
| 签名认证 | EIP-191 消息签名 (SIWE) |
| 前端代理 | Vite proxy 转发 /api 到后端 |

### 文件结构

```
backend/
├── package.json
├── tsconfig.json
├── tokenbank.db           # SQLite 数据库文件（gitignore）
└── src/
    ├── index.ts           # 服务入口
    ├── db.ts              # 数据库初始化与表结构
    ├── indexer.ts         # Transfer 事件索引器
    └── api.ts             # RESTful API 路由

frontend/src/
├── App.tsx                # 新增 SIWE 登录 + 转账记录面板
├── App.scss               # 新增转账表格样式
└── vite.config.ts         # 新增 /api 代理配置
```

### 启动方式

```bash
# 终端 1 — 启动 Anvil 本地链
anvil --port 8545

# 终端 2 — 部署合约
forge script script/DeployTokenBank.s.sol:DeployTokenBank \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 终端 3 — 启动后端
cd backend && npm install && npm run dev

# 终端 4 — 启动前端
cd frontend && npm install && npm run dev
```
