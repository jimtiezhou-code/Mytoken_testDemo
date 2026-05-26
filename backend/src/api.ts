import { Router, Request, Response } from 'express';
import db from './db.js';

const router = Router();

// GET /api/transfers/:address — get all transfers for an address
router.get('/transfers/:address', (req: Request, res: Response) => {
  const { address } = req.params;
  const { limit = '50', offset = '0' } = req.query;

  const normalizedAddress = address.toLowerCase();

  const countStmt = db.prepare(`
    SELECT COUNT(*) as total FROM transfers
    WHERE lower(from_address) = ? OR lower(to_address) = ?
  `);
  const { total } = countStmt.get(normalizedAddress, normalizedAddress) as { total: number };

  const stmt = db.prepare(`
    SELECT id, tx_hash, block_number, from_address, to_address, amount, timestamp, created_at
    FROM transfers
    WHERE lower(from_address) = ? OR lower(to_address) = ?
    ORDER BY block_number DESC, id DESC
    LIMIT ? OFFSET ?
  `);
  const rows = stmt.all(
    normalizedAddress,
    normalizedAddress,
    Number(limit),
    Number(offset)
  );

  res.json({
    success: true,
    data: rows,
    pagination: {
      total,
      limit: Number(limit),
      offset: Number(offset),
    },
  });
});

// GET /api/transfers — get all transfers (paginated)
router.get('/transfers', (_req: Request, res: Response) => {
  const limit = Number(_req.query.limit) || 50;
  const offset = Number(_req.query.offset) || 0;

  const countStmt = db.prepare('SELECT COUNT(*) as total FROM transfers');
  const { total } = countStmt.get() as { total: number };

  const stmt = db.prepare(`
    SELECT id, tx_hash, block_number, from_address, to_address, amount, timestamp, created_at
    FROM transfers
    ORDER BY block_number DESC, id DESC
    LIMIT ? OFFSET ?
  `);
  const rows = stmt.all(limit, offset);

  res.json({
    success: true,
    data: rows,
    pagination: { total, limit, offset },
  });
});

export default router;
