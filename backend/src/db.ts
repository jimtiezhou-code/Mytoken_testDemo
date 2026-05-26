import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.join(__dirname, '..', 'tokenbank.db');

const db = new Database(DB_PATH);

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS transfers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tx_hash TEXT NOT NULL,
    block_number INTEGER NOT NULL,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE UNIQUE INDEX IF NOT EXISTS idx_transfers_tx_hash_log
  ON transfers(tx_hash, from_address, to_address)
`);

db.exec(`
  CREATE INDEX IF NOT EXISTS idx_transfers_from ON transfers(from_address)
`);

db.exec(`
  CREATE INDEX IF NOT EXISTS idx_transfers_to ON transfers(to_address)
`);

export default db;
