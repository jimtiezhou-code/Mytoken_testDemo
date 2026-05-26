import { createPublicClient, http, parseAbiItem } from 'viem';
import { hardhat } from 'viem/chains';
import db from './db.js';

const TOKEN_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
const POLL_INTERVAL_MS = 3000;

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

function ingestLogs(logs: any[]) {
  const insertMany = db.transaction(() => {
    for (const log of logs) {
      const { transactionHash, blockNumber, args } = log;
      insertTransfer.run(
        transactionHash ?? 'unknown',
        Number(blockNumber),
        args.from,
        args.to,
        args.value.toString(),
        Math.floor(Date.now() / 1000)
      );
    }
  });
  insertMany();
}

async function syncRange(fromBlock: bigint, toBlock: bigint) {
  const BATCH_SIZE = 2000n;
  let currentFrom = fromBlock;
  let total = 0;

  while (currentFrom <= toBlock) {
    const currentTo = currentFrom + BATCH_SIZE - 1n > toBlock ? toBlock : currentFrom + BATCH_SIZE - 1n;

    try {
      const logs = await client.getLogs({
        address: TOKEN_ADDRESS,
        event: transferEvent,
        fromBlock: currentFrom,
        toBlock: currentTo,
      });

      if (logs.length > 0) {
        ingestLogs(logs);
        total += logs.length;
      }
    } catch (err) {
      console.error(`[Indexer] Error syncing blocks ${currentFrom}-${currentTo}:`, err);
    }

    currentFrom = currentTo + 1n;
  }

  if (total > 0) {
    console.log(`[Indexer] Synced ${total} events from blocks ${fromBlock}-${toBlock}`);
  }
}

export async function startIndexer() {
  console.log('[Indexer] Starting event indexer (polling mode)...');

  // Get last synced block from DB, or start from 0
  const lastBlockRow = db.prepare('SELECT MAX(block_number) as last_block FROM transfers').get() as { last_block: number | null };
  let lastSynced = lastBlockRow?.last_block ? BigInt(lastBlockRow.last_block) : 0n;

  const latestBlock = await client.getBlockNumber();
  console.log(`[Indexer] Last synced block: ${lastSynced}, chain head: ${latestBlock}`);

  // Catch up on any missed blocks
  if (lastSynced < latestBlock) {
    await syncRange(lastSynced, latestBlock);
    lastSynced = latestBlock;
  }

  console.log('[Indexer] Initial sync complete, starting polling...');

  // Poll for new blocks
  setInterval(async () => {
    try {
      const head = await client.getBlockNumber();
      if (head > lastSynced) {
        const from = lastSynced + 1n;
        await syncRange(from, head);
        lastSynced = head;
      }
    } catch (err) {
      // silently retry on next interval
    }
  }, POLL_INTERVAL_MS);
}
