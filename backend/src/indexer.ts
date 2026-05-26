import { createPublicClient, http, parseAbiItem } from 'viem';
import { hardhat } from 'viem/chains';
import db from './db.js';

const TOKEN_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';

const transferEvent = parseAbiItem(
  'event Transfer(address indexed from, address indexed to, uint256 value)'
);

const client = createPublicClient({
  chain: hardhat,
  transport: http('http://127.0.0.1:8545'),
});

const insertTransfer = db.prepare(`
  INSERT OR IGNORE INTO transfers (tx_hash, block_number, from_address, to_address, amount, timestamp)
  VALUES (?, ?, ?, ?, ?, ?)
`);

async function syncHistoricalLogs(fromBlock: bigint, toBlock: bigint) {
  const BATCH_SIZE = 2000n;
  let currentFrom = fromBlock;

  while (currentFrom <= toBlock) {
    const currentTo = currentFrom + BATCH_SIZE - 1n > toBlock ? toBlock : currentFrom + BATCH_SIZE - 1n;

    try {
      const logs = await client.getLogs({
        address: TOKEN_ADDRESS,
        event: transferEvent,
        fromBlock: currentFrom,
        toBlock: currentTo,
      });

      const insertMany = db.transaction(() => {
        for (const log of logs) {
          const { transactionHash, blockNumber, args } = log;
          insertTransfer.run(
            transactionHash ?? 'unknown',
            Number(blockNumber),
            (args as unknown as { from: string; to: string; value: bigint }).from,
            (args as unknown as { from: string; to: string; value: bigint }).to,
            ((args as unknown as { from: string; to: string; value: bigint }).value).toString(),
            Math.floor(Date.now() / 1000)
          );
        }
      });

      if (logs.length > 0) {
        insertMany();
        console.log(`[Indexer] Synced ${logs.length} events from blocks ${currentFrom}-${currentTo}`);
      }
    } catch (err) {
      console.error(`[Indexer] Error syncing blocks ${currentFrom}-${currentTo}:`, err);
    }

    currentFrom = currentTo + 1n;
  }
}

export async function startIndexer() {
  console.log('[Indexer] Starting event indexer...');

  // Sync historical events - from block 0 to latest
  const latestBlock = await client.getBlockNumber();
  console.log(`[Indexer] Current block: ${latestBlock}`);

  // Sync from block 0 to latest
  await syncHistoricalLogs(0n, latestBlock);
  console.log('[Indexer] Historical sync complete');

  // Watch for new events
  client.watchEvent({
    address: TOKEN_ADDRESS,
    event: transferEvent,
    onLogs: (logs) => {
      const insertMany = db.transaction(() => {
        for (const log of logs) {
          const { transactionHash, blockNumber, args } = log;
          insertTransfer.run(
            transactionHash ?? 'unknown',
            Number(blockNumber),
            (args as unknown as { from: string; to: string; value: bigint }).from,
            (args as unknown as { from: string; to: string; value: bigint }).to,
            ((args as unknown as { from: string; to: string; value: bigint }).value).toString(),
            Math.floor(Date.now() / 1000)
          );
        }
      });
      if (logs.length > 0) {
        insertMany();
        console.log(`[Indexer] Indexed ${logs.length} new transfer events`);
      }
    },
  });

  console.log('[Indexer] Watching for new Transfer events...');
}
