/**
 * palace-mint.ts — Bridge script invoked by `jelly palace mint` (Zig → Bun).
 *
 * Argv: <staging_path> <bundle_path>
 *
 * Responsibility:
 *   Read the bundle manifest and staged envelopes, open the ServerStore, and
 *   mirror the palace-minted event into LadybugDB. Exit 0 on success; non-zero
 *   on any failure (Zig rolls back the staging dir on non-zero).
 *
 * What it writes (S3.2 / AC3 + S4.1 / AC1, AC5):
 *   1. Palace node via store.ensurePalace(palaceFp)
 *   2. Genesis Mythos node + MYTHOS_HEAD edge via store.setMythosHead(palaceFp, mythosFp)
 *   3. Oracle Agent node + Palace→Agent CONTAINS edge
 *   4. Oracle Agent's knowledge-graph slot seeded with (palace-fp, "mythos-head", mythos-fp)
 *      triple via store.insertTriple — the native Triple node path now, NOT the
 *      prior Agent.knowledge_graph JSON column which has been removed from the
 *      schema (see schema.cypher `Triple` node table).
 *   5. Oracle Agent's remaining 4 slots (personality_master_prompt, memory,
 *      emotional_register, interaction_set) populated from seed via parameter-safe
 *      interpolation.
 *   6. ActionLog row + graph mirror via mirrorAction(exec, action)
 *
 * SEC11: Zig orchestrates atomicity — the bridge only writes DB rows; it does NOT
 *        touch the filesystem CAS dir.
 */

import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ServerStore } from '../../memory-palace/store.server.js';
import { mirrorAction, type MirrorAction } from '../../memory-palace/action-mirror.js';
import { sanitizeFp, cypherString } from '../../memory-palace/cypher-utils.js';

// ── Debug log (gated on JELLY_BRIDGE_DEBUG=1) ─────────────────────────────────

function debugLog(name: string, line: string): void {
  if (process.env.JELLY_BRIDGE_DEBUG !== '1') return;
  const uid = String(process.getuid?.() ?? 'nouid');
  const dir = join(tmpdir(), `dreamball-${uid}`);
  try {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    appendFileSync(join(dir, `${name}.log`), line, { mode: 0o600 });
  } catch {
    /* best effort */
  }
}

// ── Argument parsing ──────────────────────────────────────────────────────────

const [stagingPath, bundlePath] = process.argv.slice(2);

if (!stagingPath || !bundlePath) {
  console.error('palace-mint bridge: usage: <staging_path> <bundle_path>');
  process.exit(1);
}

// ── Bundle manifest parsing ───────────────────────────────────────────────────

function parseBundleLines(bundlePath: string): string[] {
  const content = readFileSync(bundlePath, 'utf-8');
  return content
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length === 64);
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  debugLog(
    'palace-mint-bridge-debug',
    `[${new Date().toISOString()}] args: stagingPath=${stagingPath} bundlePath=${bundlePath} dbPath=${process.env.PALACE_DB_PATH ?? ':memory:'}\n`
  );

  const fps = parseBundleLines(bundlePath);
  if (fps.length < 6) {
    throw new Error(
      `palace-mint bridge: expected 6 fps in bundle, got ${fps.length} (bundle: ${bundlePath})`
    );
  }

  // Bundle line order: palace_fp, oracle_fp, mythos_fp, registry_fp, action_fp, timeline_fp.
  // Only four of the six are consumed here; registry_fp and timeline_fp are
  // preserved in the bundle for Zig-side orchestration but unused on the DB side.
  const palaceFpRaw = fps[0];
  const oracleFpRaw = fps[1];
  const mythosFpRaw = fps[2];
  const actionFpRaw = fps[4];

  // Validate every fp from the bundle before any Cypher interpolation.
  const palaceFp = sanitizeFp(palaceFpRaw, 'palaceFp');
  const oracleFp = sanitizeFp(oracleFpRaw, 'oracleFp');
  const mythosFp = sanitizeFp(mythosFpRaw, 'mythosFp');
  const actionFp = sanitizeFp(actionFpRaw, 'actionFp');

  // AC7: oracle prompt comes from ORACLE_PROMPT env var (set by Zig from @embedFile).
  const oraclePrompt = process.env.ORACLE_PROMPT ?? '';

  const dbPath = process.env.PALACE_DB_PATH ?? 'palace.db';

  const store = new ServerStore(dbPath);
  await store.open();

  try {
    // 1. Ensure Palace node
    await store.ensurePalace(palaceFp, undefined, { formatVersion: 2, revision: 0 });

    // 2. Genesis Mythos node + MYTHOS_HEAD edge
    await store.setMythosHead(palaceFp, mythosFp, { isGenesis: true, actionFp });

    // 3. Oracle Agent node + Palace→Agent CONTAINS edge.
    // StoreAPI has no dedicated agent verb — the escape hatch is used here with
    // validator-gated interpolation.
    const agentExists = await store.__rawQuery(
      `MATCH (a:Agent {fp: '${oracleFp}'}) RETURN a.fp AS fp`
    );
    if (agentExists.length === 0) {
      await store.__rawQuery(
        `CREATE (:Agent {fp: '${oracleFp}', created_at: ${Date.now()}})`
      );
    }
    const containsExists = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'})-[e:CONTAINS]->(a:Agent {fp: '${oracleFp}'}) RETURN e`
    );
    if (containsExists.length === 0) {
      await store.__rawQuery(
        `MATCH (p:Palace {fp: '${palaceFp}'})
         MATCH (a:Agent {fp: '${oracleFp}'})
         CREATE (p)-[:CONTAINS]->(a)`
      );
    }

    // 4. S4.1 AC1: Populate oracle Agent's 4 JSON slots (master prompt, memory,
    //    emotional register, interaction set). knowledge_graph is now stored as
    //    native Triple nodes — see step 5.
    const emotionalRegister = JSON.stringify({
      curiosity: 0.5,
      warmth: 0.5,
      patience: 0.5,
    });
    const emptyArr = JSON.stringify([]);

    await store.__rawQuery(
      `MATCH (a:Agent {fp: '${oracleFp}'})
       SET a.personality_master_prompt = ${cypherString(oraclePrompt)},
           a.memory = ${cypherString(emptyArr)},
           a.emotional_register = ${cypherString(emotionalRegister)},
           a.interaction_set = ${cypherString(emptyArr)}`
    );

    // 5. AC5: Seed the oracle's knowledge-graph with the initial
    // (palace-fp, "mythos-head", mythos-fp) triple as a native Triple node.
    // Replaces the prior JSON blob written into Agent.knowledge_graph.
    await store.insertTriple(oracleFp, palaceFp, 'mythos-head', mythosFp);

    // 6. Mirror the palace-minted action into ActionLog
    const now = Date.now();
    const action: MirrorAction = {
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: oracleFp,
      target_fp: palaceFp,
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: actionFp,
    };

    const exec = (cypher: string) => store.__rawQuery(cypher);
    await mirrorAction(exec, action);

    console.log(`palace-mint bridge: mirrored palace ${palaceFp} → ${dbPath}`);
    console.log(`palace-mint bridge: oracle slots seeded (AC1/AC5 S4.1)`);
  } finally {
    await store.close();
  }
}

main().catch((err) => {
  const errMsg = `palace-mint bridge error: ${err}\n${(err as Error)?.stack ?? ''}\n`;
  console.error(errMsg);
  debugLog('palace-mint-bridge-error', errMsg);
  process.exit(1);
});
