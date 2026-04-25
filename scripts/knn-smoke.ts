/**
 * knn-smoke.ts — S6.3 AC9 K-NN round-trip smoke test.
 *
 * Flow: mint palace → add room → inscribe 3 docs → embed each → kNN query
 * Asserts: 3 hits returned; top-1 is one of the 3 inserted inscriptions.
 *
 * Run with JELLY_EMBED_MOCK=1 (deterministic blake3-seeded mock, no Qwen3).
 * Exit 0 on pass, 1 on failure.
 */

import { ServerStore } from '../src/memory-palace/store.server.js';
import { kNN } from '../src/memory-palace/knn.js';

function makeFp(seed: number): string {
  return seed.toString(16).padStart(16, '0').repeat(4);
}

async function main(): Promise<void> {
  if (!process.env['JELLY_EMBED_MOCK']) {
    process.env['JELLY_EMBED_MOCK'] = '1';
  }

  const store = new ServerStore(':memory:');
  await store.open();

  const palaceFp = makeFp(0x5e00);
  const roomFp = makeFp(0x5e01);

  await store.ensurePalace(palaceFp);
  await store.addRoom(palaceFp, roomFp);

  // Inscribe 3 documents with distinct content → distinct embeddings via mock
  const inscriptions = [
    { fp: makeFp(0x1001), content: 'palace of memory and resonance', src: 'a'.repeat(64) },
    { fp: makeFp(0x1002), content: 'the river flows through the garden', src: 'b'.repeat(64) },
    { fp: makeFp(0x1003), content: 'starlight and ancient archives', src: 'c'.repeat(64) },
  ];

  for (const doc of inscriptions) {
    await store.inscribeAvatar(roomFp, doc.fp, doc.src);
    // Embed and upsert each inscription
    const { embedFor } = await import('../src/memory-palace/embedding-client.js');
    const vec = await embedFor(doc.content, 'text/plain');
    await store.upsertEmbedding(doc.fp, new Float32Array(vec));
  }

  // kNN query
  const hits = await kNN(store, 'palace of memory', 3);

  if (hits.length !== 3) {
    console.error(`FAIL: expected 3 hits, got ${hits.length}`);
    await store.close();
    process.exit(1);
  }

  const knownFps = new Set(inscriptions.map((d) => d.fp));
  if (!knownFps.has(hits[0].fp)) {
    console.error(`FAIL: top-1 fp '${hits[0].fp}' not in inserted inscriptions`);
    await store.close();
    process.exit(1);
  }

  // Verify all hits have roomFp resolved
  for (const hit of hits) {
    if (!hit.roomFp || hit.roomFp.length < 8) {
      console.error(`FAIL: hit ${hit.fp} has missing/invalid roomFp: '${hit.roomFp}'`);
      await store.close();
      process.exit(1);
    }
    if (!Number.isFinite(hit.distance)) {
      console.error(`FAIL: hit ${hit.fp} has non-finite distance: ${hit.distance}`);
      await store.close();
      process.exit(1);
    }
  }

  await store.close();

  console.log(`PASS: kNN returned ${hits.length} hits`);
  console.log(`  top-1: fp=${hits[0].fp.slice(0, 12)}... roomFp=${hits[0].roomFp.slice(0, 12)}... d=${hits[0].distance.toFixed(4)}`);
  process.exit(0);
}

main().catch((err) => {
  console.error('knn-smoke error:', err);
  process.exit(1);
});
