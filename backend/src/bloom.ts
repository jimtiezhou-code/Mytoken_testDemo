import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BLOOM_PATH = path.join(__dirname, '..', 'bloom.bin');

// 预期元素数量 100,000，误判率 ~0.1%
// 公式: m = -n*ln(p) / (ln2)^2，k = (m/n)*ln2
const N_EXPECTED = 100_000;
const P_TARGET = 0.001;
const BIT_COUNT = Math.ceil((-N_EXPECTED * Math.log(P_TARGET)) / (Math.LN2 ** 2)); // ~1,437,750 bits
const BYTE_COUNT = Math.ceil(BIT_COUNT / 8);                                        // ~179,719 bytes
const HASH_COUNT = Math.round((BIT_COUNT / N_EXPECTED) * Math.LN2);                 // ~10

class BloomFilter {
  private bits: Buffer;
  private count = 0;

  constructor() {
    this.bits = Buffer.alloc(BYTE_COUNT, 0);
  }

  // 双重哈希生成 k 个位索引 (Kirsch-Mitzenmacker 方案)
  private getBits(value: string): number[] {
    const hash = crypto.createHash('sha256').update(value).digest();
    const h1 = hash.readUInt32BE(0);
    const h2 = hash.readUInt32BE(4);

    const indices: number[] = [];
    for (let i = 0; i < HASH_COUNT; i++) {
      const combined = (h1 + i * h2) % BIT_COUNT;
      indices.push(combined >= 0 ? combined : combined + BIT_COUNT);
    }
    return indices;
  }

  add(value: string): void {
    const key = value.toLowerCase();
    for (const idx of this.getBits(key)) {
      this.bits[Math.floor(idx / 8)] |= 1 << idx % 8;
    }
    this.count++;
  }

  mightContain(value: string): boolean {
    const key = value.toLowerCase();
    for (const idx of this.getBits(key)) {
      if ((this.bits[Math.floor(idx / 8)] & (1 << idx % 8)) === 0) {
        return false;
      }
    }
    return true;
  }

  save(): void {
    const data = Buffer.concat([
      Buffer.from([0xBF, 0x01]), // magic + version
      this.bits,
    ]);
    fs.writeFileSync(BLOOM_PATH, data);
    console.log(`[Bloom] Saved to disk (${this.count} addresses, ${BYTE_COUNT} bytes)`);
  }

  load(): boolean {
    if (!fs.existsSync(BLOOM_PATH)) return false;

    const data = fs.readFileSync(BLOOM_PATH);
    if (data[0] !== 0xBF || data[1] !== 0x01) {
      console.warn('[Bloom] Invalid file header, creating new filter');
      return false;
    }

    this.bits = data.subarray(2);
    // 从数据库恢复 count
    console.log(`[Bloom] Loaded from disk (${BYTE_COUNT} bytes)`);
    return true;
  }

  // 从数据库全量重建
  rebuildFromAddresses(addresses: string[]): void {
    this.bits = Buffer.alloc(BYTE_COUNT, 0);
    for (const addr of addresses) {
      const key = addr.toLowerCase();
      for (const idx of this.getBits(key)) {
        this.bits[Math.floor(idx / 8)] |= 1 << idx % 8;
      }
    }
    this.count = addresses.length;
    this.save();
    console.log(`[Bloom] Rebuilt from ${addresses.length} addresses`);
  }
}

export const bloomFilter = new BloomFilter();
export { BLOOM_PATH };
