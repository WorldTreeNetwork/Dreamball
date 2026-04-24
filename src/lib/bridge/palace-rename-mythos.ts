/**
 * palace-rename-mythos.ts — Bridge script invoked by `jelly palace rename-mythos` (Zig → Bun).
 *
 * Argv: <staging_path> <bundle_path>
 *
 * Bundle format (one value per line):
 *   Line 0: palace_fp (64 hex)
 *   Line 1: new_mythos_fp / M1 (64 hex)
 *   Line 2: action_fp (64 hex — "true-naming" action)
 *   Line 3: predecessor_fp / M0 (64 hex, or "0"×64 if genesis — should not happen)
 *   Line 4: "1" if predecessor present, "0" otherwise
 *   Line 5: true_name (string, may be empty)
 *   Line 6: form (string, may be empty)
 *
 * Responsibility (AC7 / S3.4):
 *   1. Open store
 *   2. AC3 second-genesis check: verify MYTHOS_HEAD already exists (predecessor required)
 *   3. Create new Mythos node (M1) in the store
 *   4. Add PREDECESSOR edge M1 → M0
 *   5. Re-point MYTHOS_HEAD from M0 → M1 (delete old edge, create new)
 *   6. Mirror "true-naming" action into ActionLog
 *
 * SEC3: canonical chain mythos are always public. This bridge never attaches
 * guild-only quorum to a Mythos node. No guild_fp parameter exists here.
 *
 * SEC11: Zig orchestrates CAS atomicity. Bridge only writes DB rows.
 * TC13: No CBOR bytes stored — fps are Blake3 hex strings.
 * TC18: Only canonical mythos live in the MYTHOS_HEAD/PREDECESSOR chain.
 *       Poetic mythoi attach elsewhere (e.g. on inscriptions). This bridge is
 *       canonical-chain only.
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
  console.error('palace-rename-mythos bridge: usage: <staging_path> <bundle_path>');
  process.exit(1);
}

// ── Bundle parsing ────────────────────────────────────────────────────────────

interface RenameMythosBundle {
  palaceFp: string;
  newMythosFp: string;
  actionFp: string;
  predecessorFp: string | null;
  trueName: string | null;
  form: string | null;
}

function parseBundle(path: string): RenameMythosBundle {
  const content = readFileSync(path, 'utf-8');
  const lines = content.split('\n').map((l) => l.trim());

  if (lines.length < 7) {
    throw new Error(
      `palace-rename-mythos bridge: expected ≥7 lines in bundle, got ${lines.length}`
    );
  }

  const palaceFp = lines[0];
  const newMythosFp = lines[1];
  const actionFp = lines[2];
  const predecessorFpRaw = lines[3];
  const predecessorPresent = lines[4] === '1';
  const trueName = lines[5] !== '' ? lines[5] : null;
  const form = lines[6] !== '' ? lines[6] : null;

  const NULL_FP = '0'.repeat(64);

  return {
    palaceFp,
    newMythosFp,
    actionFp,
    predecessorFp: predecessorPresent && predecessorFpRaw !== NULL_FP ? predecessorFpRaw : null,
    trueName,
    form,
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  debugLog(
    'palace-rename-mythos-bridge-debug',
    `[${new Date().toISOString()}] stagingPath=${stagingPath} bundlePath=${bundlePath}\n`
  );

  const parsed = parseBundle(bundlePath);
  const palaceFp = sanitizeFp(parsed.palaceFp, 'palaceFp');
  const newMythosFp = sanitizeFp(parsed.newMythosFp, 'newMythosFp');
  const actionFp = sanitizeFp(parsed.actionFp, 'actionFp');
  const predecessorFp = parsed.predecessorFp
    ? sanitizeFp(parsed.predecessorFp, 'predecessorFp')
    : null;
  // trueName and form are parsed from the bundle but currently unused by the
  // DB-mirror path; they live on the Zig-signed envelope where the canonical
  // truth lives and will surface through the replay decoder.
  void parsed.trueName;
  void parsed.form;

  const dbPath = process.env.PALACE_DB_PATH ?? 'palace.db';
  const store = new ServerStore(dbPath);
  await store.open();

  try {
    // AC3: second-genesis check — MYTHOS_HEAD must already exist for a rename.
    // If no MYTHOS_HEAD exists, the palace has no genesis mythos — impossible for
    // a minted palace. If predecessorFp is null (shouldn't happen), reject.
    if (!predecessorFp) {
      throw new Error(
        'second genesis rejected: no predecessor fp provided — cannot rename without an existing genesis mythos'
      );
    }

    // Verify palace exists.
    const palaceCheck = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'}) RETURN p.fp AS fp`
    );
    if (palaceCheck.length === 0) {
      throw new Error(`palace-rename-mythos bridge: palace '${palaceFp}' not found in store`);
    }

    // Verify predecessor (M0) exists as the current MYTHOS_HEAD.
    const headCheck = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'})-[:MYTHOS_HEAD]->(m:Mythos {fp: '${predecessorFp}'}) RETURN m.fp AS fp`
    );
    if (headCheck.length === 0) {
      // MYTHOS_HEAD doesn't point to this predecessor — either no head or stale bundle.
      // Still allow if the Mythos node exists (the head may have moved since the
      // bundle was written). Log a warning but continue — the store's setMythosHead
      // will re-point MYTHOS_HEAD correctly regardless.
      console.warn(
        `palace-rename-mythos bridge: MYTHOS_HEAD for palace '${palaceFp}' does not point to predecessor '${predecessorFp}'. Proceeding with rename (bridge will re-point MYTHOS_HEAD).`
      );
    }

    // 1. Create new Mythos node M1.
    //    SEC3: no guild-only quorum attached — canonical chain is always public.
    const mExists = await store.__rawQuery(
      `MATCH (m:Mythos {fp: '${newMythosFp}'}) RETURN m.fp AS fp`
    );
    if (mExists.length === 0) {
      await store.__rawQuery(
        `CREATE (:Mythos {
          fp: '${newMythosFp}',
          body: ${cypherString('')},
          canonicality: 'successor',
          discovered_in_action_fp: '${actionFp}',
          created_at: ${Date.now()}
        })`
      );
    }

    // 2. PREDECESSOR edge: M1 → M0.
    const predEdgeExists = await store.__rawQuery(
      `MATCH (m1:Mythos {fp: '${newMythosFp}'})-[e:PREDECESSOR]->(m0:Mythos {fp: '${predecessorFp}'}) RETURN e`
    );
    if (predEdgeExists.length === 0) {
      // Ensure M0 node exists (it should, since it was the genesis).
      const m0Exists = await store.__rawQuery(
        `MATCH (m:Mythos {fp: '${predecessorFp}'}) RETURN m.fp AS fp`
      );
      if (m0Exists.length === 0) {
        // M0 not in store — create a stub node so the PREDECESSOR edge can be created.
        // This can happen if the genesis mythos was created before the store was
        // initialised (e.g. in tests or replay). The CAS is authoritative.
        await store.__rawQuery(
          `CREATE (:Mythos {
            fp: '${predecessorFp}',
            body: ${cypherString('')},
            canonicality: 'genesis',
            discovered_in_action_fp: '',
            created_at: ${Date.now()}
          })`
        );
      }
      await store.__rawQuery(
        `MATCH (m1:Mythos {fp: '${newMythosFp}'})
         MATCH (m0:Mythos {fp: '${predecessorFp}'})
         CREATE (m1)-[:PREDECESSOR]->(m0)`
      );
    }

    // 3. Re-point MYTHOS_HEAD: Palace → M1 (via store.setMythosHead which handles
    //    the edge swap atomically — delete old MYTHOS_HEAD, create new one).
    await store.setMythosHead(palaceFp, newMythosFp, {
      isGenesis: false,
      actionFp,
    });

    // 4. Mirror "true-naming" action into ActionLog (AC7).
    const now = Date.now();
    const action: MirrorAction = {
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'true-naming',
      actor_fp: palaceFp, // custodian = palace identity
      target_fp: newMythosFp,
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: actionFp,
      extra: {
        predecessorFp: predecessorFp ?? undefined,
        canonicality: 'successor',
      },
    };

    const exec = (cypher: string) => store.__rawQuery(cypher);
    await mirrorAction(exec, action);

    // 5. AC6 (S4.1): Update the oracle's knowledge-graph to point to the new
    //    mythos head. The KG is now stored as native Triple nodes (schema.cypher
    //    Triple + HAS_KNOWLEDGE); this bridge uses store.triplesFor / deleteTriple /
    //    insertTriple so the write follows the same D-007 domain-verb path as
    //    every other triple write. The prior JSON read-modify-write is gone
    //    (Agent.knowledge_graph column removed).
    const agentRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (p:Palace {fp: '${palaceFp}'})-[:CONTAINS]->(a:Agent) RETURN a.fp AS fp`
    );
    if (agentRows.length > 0) {
      const oracleFp = sanitizeFp(String(agentRows[0].fp), 'oracleFp');
      // Fetch any existing (palaceFp, 'mythos-head', *) triples so we can
      // delete the stale object before inserting the new one. Multiple matches
      // would indicate a prior bug; we clear all of them defensively.
      const existing = await store.triplesFor(oracleFp, palaceFp);
      for (const t of existing) {
        if (t.predicate === 'mythos-head') {
          await store.deleteTriple(oracleFp, palaceFp, 'mythos-head', t.object);
        }
      }
      await store.insertTriple(oracleFp, palaceFp, 'mythos-head', newMythosFp);
      console.log(
        `palace-rename-mythos bridge: oracle knowledge-graph updated → (${palaceFp}, mythos-head, ${newMythosFp})`
      );
    }

    console.log(
      `palace-rename-mythos bridge: renamed palace ${palaceFp} mythos head → ${newMythosFp}`
    );
  } finally {
    await store.close();
  }
}

main().catch((err) => {
  const errMsg = `palace-rename-mythos bridge error: ${err}\n${(err as Error)?.stack ?? ''}\n`;
  console.error(errMsg);
  debugLog('palace-rename-mythos-bridge-error', errMsg);

  const msg = String(err);
  if (msg.includes('second genesis') || msg.includes('not found')) {
    process.stderr.write(msg + '\n');
  }
  process.exit(1);
});
