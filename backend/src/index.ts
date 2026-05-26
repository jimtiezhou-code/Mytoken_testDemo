import express from 'express';
import cors from 'cors';
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

app.listen(PORT, () => {
  console.log(`[Server] Backend running at http://localhost:${PORT}`);
  startIndexer().catch((err) => {
    console.error('[Server] Failed to start indexer:', err);
  });
});
