/**
 * run-knn-perf.ts — S6.3 AC3 perf runner (R5 mitigation).
 *
 * Called by scripts/perf/embedding.sh with JELLY_EMBED_MOCK=1.
 * Measures ONLY the kNN query round-trip (query-embed + vector-index lookup).
 * Corpus setup (500 CREATE + upsertEmbedding) is excluded from timing.
 *
 * Exit:
 *   0 — p50 <200ms (hard gate passed)
 *   1 — p50 >= 200ms (HARD BLOCK)
 *
 * Output lines:
 *   p50=Xms p95=Xms n=10 corpus=500
 *   budget-met | warn-threshold-near-budget
 */

import { ServerStore } from '../../src/memory-palace/store.server.js';
import { kNN } from '../../src/memory-palace/knn.js';
import {
  generatePerfCorpus,
  generatePerfQueryVector,
  perfRoomFps,
} from '../../src/memory-palace/perf-fixtures.js';

const N_RUNS = 10;
const CORPUS_SIZE = 500;
const K = 10;
const P50_BUDGET_MS = 200;
const P95_SOFT_MS = 400;

function makeFp(seed: number): string {
  return seed.toString(16).padStart(16, '0').repeat(4);
}

async function main(): Promise<void> {
  console.log('Setting up 500-inscription corpus...');

  const store = new ServerStore(':memory:');
  await store.open();

  const corpus = generatePerfCorpus(CORPUS_SIZE, 256, 42);
  const rooms = perfRoomFps();

  // Setup: palace + rooms + inscriptions + embeddings (NOT timed)
  const palaceFp = makeFp(0xbeef);
  await store.ensurePalace(palaceFp);
  for (const roomFp of rooms) {
    await store.addRoom(palaceFp, roomFp);
  }

  for (const insc of corpus) {
    await store.inscribeAvatar(insc.roomFp, insc.fp, insc.sourceBlake3);
    await store.upsertEmbedding(insc.fp, insc.vec);
  }

  console.log(`Corpus ready: ${CORPUS_SIZE} inscriptions in ${rooms.length} rooms.`);

  // Warm up (1 call, not measured)
  const queryVec = generatePerfQueryVector(256, 99);
  await kNN(store, 'warmup', K);

  // Measure N_RUNS consecutive kNN calls
  const latencies: number[] = [];
  for (let i = 0; i < N_RUNS; i++) {
    const t0 = performance.now();
    const hits = await kNN(store, 'query text', K);
    const t1 = performance.now();
    latencies.push(t1 - t0);

    if (hits.length !== K) {
      console.error(`Run ${i}: expected ${K} hits, got ${hits.length}`);
      process.exit(1);
    }
  }

  await store.close();

  latencies.sort((a, b) => a - b);
  const p50 = latencies[Math.floor(N_RUNS * 0.5)];
  const p95 = latencies[Math.floor(N_RUNS * 0.95)] ?? latencies[latencies.length - 1];

  console.log(
    `p50=${p50.toFixed(1)}ms p95=${p95.toFixed(1)}ms n=${N_RUNS} corpus=${CORPUS_SIZE}`
  );

  if (p50 >= P50_BUDGET_MS) {
    console.error(
      `HARD BLOCK: p50=${p50.toFixed(1)}ms >= ${P50_BUDGET_MS}ms budget`
    );
    process.exit(1);
  }

  if (p95 >= P95_SOFT_MS) {
    console.log(
      `warn-threshold-near-budget: p95=${p95.toFixed(1)}ms >= ${P95_SOFT_MS}ms soft ceiling`
    );
  } else {
    console.log('budget-met');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('perf runner error:', err);
  process.exit(1);
});
