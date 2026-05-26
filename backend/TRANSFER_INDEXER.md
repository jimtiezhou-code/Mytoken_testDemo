# ERC20 转账事件索引 & 查询系统

## 整体架构

```
┌─────────────┐    Transfer 事件     ┌──────────────┐   poll / getLogs   ┌──────────┐
│  Anvil 节点  │ ◄────────────────── │   Indexer     │ ─────────────────► │ SQLite3  │
│  (HTTP 8545) │                     │   (后端轮询)   │                    │ transfers │
└─────────────┘                      └──┬───┬───────┘                    └────┬─────┘
                                        │   │                                │
                                        │   └── add(from)/add(to) ────┐     │
                                        │                              ▼     │
                                        │                         ┌──────────┐
                                        │                         │  Bloom   │
                                     Express API                  │  Filter  │
                              GET /api/transfers/:addr            │ bloom.bin│
                                        │                         └────┬─────┘
                                        │                              │
                                        └──── mightContain(addr) ─────┘
                                        │
                                 ┌──────┴───────┐
                                 │  Vite Proxy   │
                                 │  :5173 → :3001│
                                 └──────┬───────┘
                                        │
                                 ┌──────┴───────┐
                                 │   Frontend    │
                                 │  React App    │
                                 └──────────────┘
```

## 一、数据库设计 (db.ts)

### 表结构

```sql
CREATE TABLE IF NOT EXISTS transfers (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    tx_hash      TEXT    NOT NULL,    -- 交易哈希
    block_number INTEGER NOT NULL,    -- 区块号
    from_address TEXT    NOT NULL,    -- 发送方地址
    to_address   TEXT    NOT NULL,    -- 接收方地址
    amount       TEXT    NOT NULL,    -- 金额 (字符串存储, 避免 uint256 溢出)
    timestamp    INTEGER NOT NULL,    -- Unix 时间戳
    created_at   TEXT    DEFAULT (datetime('now'))
);
```

### 索引

| 索引名 | 字段 | 类型 | 作用 |
|--------|------|------|------|
| `idx_transfers_tx_hash_log` | (tx_hash, from_address, to_address) | UNIQUE | 去重, 同一笔交易同一组 from/to 只存一条 |
| `idx_transfers_from` | from_address | 普通 | 加速按发送方查询 |
| `idx_transfers_to` | to_address | 普通 | 加速按接收方查询 |

### 关键设计决策

- **amount 用 TEXT 存储**: ERC20 的 uint256 值可能超过 JS Number 范围, 字符串避免精度丢失
- **UNIQUE 索引做幂等**: `INSERT OR IGNORE` 配合唯一索引, 重复轮询同一区块不会产生重复数据
- **WAL 模式**: `PRAGMA journal_mode = WAL` 提升并发读写性能

## 二、事件索引器 (indexer.ts)

### 核心流程

```
startIndexer()
  │
  ├─ 1. 查 DB 中已同步的最大区块号 → lastSynced
  │
  ├─ 2. 查链上最新区块号 → latestBlock
  │
  ├─ 3. 追赶历史: syncRange(lastSynced, latestBlock)
  │     └─ 分批查询 (每批 2000 个区块)
  │          └─ client.getLogs({ address, event, fromBlock, toBlock })
  │               └─ ingestLogs() → INSERT OR IGNORE into transfers
  │
  └─ 4. setInterval 每 3 秒轮询新块
        └─ head > lastSynced ?
             └─ syncRange(lastSynced + 1, head) → 更新 lastSynced
```

### 为什么要用轮询而不是 watchEvent？

`watchEvent` 底层依赖 `eth_subscribe`（WebSocket）或 `eth_newFilter`（HTTP），Anvil 的 HTTP 端点对这两种方式支持不稳定。改用 `getLogs` 主动轮询更可靠。

### viem getLogs 入参说明

```ts
const logs = await client.getLogs({
  address: TOKEN_ADDRESS,               // 只查 BERC20 合约的日志
  event: parseAbiItem(                  // 按事件签名过滤
    'event Transfer(address indexed from, address indexed to, uint256 value)'
  ),
  fromBlock: 0n,    // 起始区块
  toBlock: 100n,    // 结束区块
});
```

返回的每条 log 结构：
```
{
  transactionHash: "0xad5b...",    // 交易哈希
  blockNumber: 3n,                 // 区块号
  args: {
    from: "0xf39F...",             // 发送方 (indexed topic 解码后)
    to:   "0x7099...",             // 接收方
    value: 100000000000000000000n  // 金额 (uint256)
  }
}
```

### 断点续传

- 每次启动时从 DB 查 `MAX(block_number)` 作为 `lastSynced`
- 只同步 `lastSynced` 到链头之间的新区块
- 重启不会丢失进度, 也不会重复处理已入库的事件 (INSERT OR IGNORE)

## 三、布隆过滤器 (bloom.ts)

### 为什么需要布隆过滤器？

API 查询某地址的转账记录时，如果该地址**从未**参与过任何转账，可以直接返回空数组，跳过 SQLite 的 B-Tree 索引扫描。

布隆过滤器是一个概率型数据结构，特点是：

- `mightContain(x) = false` → x **一定不在**集合中（100% 准确）
- `mightContain(x) = true`  → x **可能**在集合中（有误判率）

所以我们用它做**快速否决**：过滤器说"没有"就直接返回空，说"可能有"才走 DB。

### 实现原理

```
添加地址 "0xf39F..."
  └─ .toLowerCase() → "0xf39f..."
       └─ SHA256 哈希 → 取前 8 字节得 h1, h2
            └─ Kirsch-Mitzenmacker: bit_i = (h1 + i * h2) % BIT_COUNT (i = 0..9)
                 └─ 将 buffer 中第 bit_i 位置 1

查询地址 "0xf39F..."
  └─ 同样计算 10 个位
       └─ 所有位都是 1 → "可能有" (走 DB 查)
       └─ 任一位是 0   → "一定没有" (直接返回空)
```

### 参数选取

```
预期元素数 n = 100,000      (预计最多 10 万个不同地址)
目标误判率 p = 0.001       (0.1%)
────────────────────────────────────────
位数组大小 m = -n·ln(p) / (ln2)² ≈ 1,437,750 bits ≈ 175 KB
哈希函数数 k = (m/n)·ln2           ≈ 10
```

175 KB 常驻内存，10 次位运算判断，成本极低。

### 持久化

- **文件**: `backend/bloom.bin`（二进制，~175 KB）
- **格式**: `[0xBF, 0x01]` (magic + version) + 位数组
- **保存时机**: 索引器初次同步完成后 + 每次轮询到新数据后
- **恢复**: 启动时从 `bloom.bin` 加载，文件不存在则从 SQLite 全量重建

### 在查询链路中的位置

```
API: GET /api/transfers/:address
  │
  ├─ bloomFilter.mightContain(address)
  │    ├─ false → 直接返回 { data: [], total: 0 }   ← 跳过 DB
  │    └─ true  → 继续走 SQLite 查询
  │
  └─ SELECT * FROM transfers WHERE ...
```

## 四、RESTful API (api.ts)

### 端点说明

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/transfers/:address` | 查询某地址的转入+转出记录 |
| GET | `/api/transfers` | 查询全部转账记录 |

### 请求示例

```bash
# 查询 Account #0 的转账记录
curl http://localhost:3001/api/transfers/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# 分页参数
curl "http://localhost:3001/api/transfers/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266?limit=10&offset=0"
```

### 响应格式

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "tx_hash": "0xad5b9d102c3f2b7961259e5d8aafd3c817bf5d4eb8b333142b7c439e06e8cdce",
      "block_number": 3,
      "from_address": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      "to_address": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      "amount": "100000000000000000000",
      "timestamp": 1779783712,
      "created_at": "2026-05-26 08:21:52"
    }
  ],
  "pagination": {
    "total": 5,
    "limit": 50,
    "offset": 0
  }
}
```

### 查询逻辑

```sql
-- 核心查询: 地址匹配 from 或 to 即为相关转账
SELECT * FROM transfers
WHERE lower(from_address) = ? OR lower(to_address) = ?
ORDER BY block_number DESC, id DESC
LIMIT ? OFFSET ?
```

大小写不敏感匹配 (`lower()`), 结果按区块逆序排列 (最新的在前)。

## 五、前后端通信链路

```
用户点击「刷新」
  └─ fetchTransfers(address)
       └─ fetch(`/api/transfers/${address}?limit=100`)
            │
            ├─ Vite dev server 收到请求 (localhost:5173)
            │    └─ server.proxy 规则: /api → http://localhost:3001
            │
            ├─ Express 收到 GET /api/transfers/0xf39F...
            │    └─ api.ts Router 处理
            │         └─ db.prepare().all() 查询 SQLite
            │
            └─ 返回 JSON → App.tsx setTransfers() → React 渲染表格
```

## 六、前端状态管理

```
连接钱包 (useConnect)
  └─ isConnected = true, address 可用
       └─ 用户点击「登录」
            └─ handleSIWE()
                 ├─ signMessageAsync() → MetaMask 弹签名
                 ├─ setSiweAuthed(true)
                 └─ fetchTransfers(address) → 首次加载记录

切换 MetaMask 账户
  └─ address 变化 (useAccount 自动检测)
       └─ useEffect 触发
            ├─ setSiweAuthed(false)  // 重置登录状态
            └─ setTransfers([])       // 清空旧记录
       └─ 用户需要重新点击「登录」完成新地址的签名
```

## 七、文件清单

```
backend/
├── bloom.bin           — 布隆过滤器持久化文件 (gitignore)
├── tokenbank.db        — SQLite3 数据库 (gitignore)
├── src/
│   ├── index.ts        — 服务入口, 启动 Express + Indexer + Bloom
│   ├── db.ts           — SQLite3 建表 + 索引
│   ├── bloom.ts        — 布隆过滤器实现 (SHA256 双重哈希)
│   ├── indexer.ts      — Transfer 事件轮询索引器
│   └── api.ts          — 转账记录查询接口 (含 Bloom 预判)

frontend/src/
├── App.tsx          — SIWE 登录 + 转账记录面板
├── App.scss         — 转账表格样式
└── vite.config.ts   — /api 代理配置
```
