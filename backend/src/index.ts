import express from 'express';
import cors from 'cors';
import db from './db.js';
import { bloomFilter } from './bloom.js';
import { startIndexer } from './indexer.js';
import apiRouter from './api.js';

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

app.use('/api', apiRouter);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// 布隆过滤器初始化：从磁盘加载，文件不存在则从数据库重建
if (!bloomFilter.load()) {
  console.log('[Server] Bloom filter not found, rebuilding from database...');
  const rows = db.prepare('SELECT DISTINCT from_address AS addr FROM transfers UNION SELECT DISTINCT to_address AS addr FROM transfers').all() as { addr: string }[];
  bloomFilter.rebuildFromAddresses(rows.map((r) => r.addr));
}

app.listen(PORT, () => {
  console.log(`[Server] Backend running at http://localhost:${PORT}`);
  startIndexer().catch((err) => {
    console.error('[Server] Failed to start indexer:', err);
  });
});
