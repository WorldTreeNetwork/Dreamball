/**
 * palace-inscribe.ts — Bridge script invoked by `jelly palace inscribe` (Zig → Bun).
 *
 * Argv: <staging_path> <bundle_path>
 *
 * Bundle format (one value per line):
 *   Line 0: palace_fp (64 hex)
 *   Line 1: room_fp (64 hex)
 *   Line 2: inscription_fp (64 hex)
 *   Line 3: action_fp (64 hex)
 *   Line 4: source_blake3 (64 hex)
 *   Line 5: mythos_fp (64 hex, or "0"×64 if absent)
 *   Line 6: archiform_fp (64 hex, or "0"×64 if absent)
 *   Line 7: "1" if mythos present, "0" otherwise
 *   Line 8: "1" if archiform present, "0" otherwise
 *
 * Responsibility:
 *   1. AC3: verify room_fp is contained by palace
 *   2. AC6 cycle check: inscription_fp must not already exist in this palace
 *   3. store.inscribeAvatar(roomFp, inscriptionFp, sourceBlake3, { archiform? })
 *   4. AC8: lazy aqueduct between palace and room (store.getOrCreateAqueduct)
 *   5. Optionally create Mythos node for inscription
 *   6. mirrorAction for "avatar-inscribed"
 *   7. mirrorAction for "aqueduct-created" if aqueduct was newly created (AC8)
 *
 * SEC11: Zig orchestrates CAS atomicity. Bridge only writes DB rows.
 * TC13: No CBOR bytes stored.
 * AC3: Unknown room → stderr "room not in palace"; exit non-zero.
 * AC8: Lazy aqueduct created between (palace_fp, room_fp) on inscribe.
 */

import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ServerStore } from '../../memory-palace/store.server.js';
import { mirrorAction, type MirrorAction } from '../../memory-palace/action-mirror.js';
import { mirrorInscriptionToKnowledgeGraph } from '../../memory-palace/oracle.js';
import { sanitizeFp, deriveTripleFp } from '../../memory-palace/cypher-utils.js';

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
  console.error('palace-inscribe bridge: usage: <staging_path> <bundle_path>');
  process.exit(1);
}

// ── Bundle parsing ────────────────────────────────────────────────────────────

interface InscribeBundle {
  palaceFp: string;
  roomFp: string;
  inscriptionFp: string;
  actionFp: string;
  sourceBlake3: string;
  mythosFp: string | null;
  archiformFp: string | null;
}

function parseBundle(path: string): InscribeBundle {
  const content = readFileSync(path, 'utf-8');
  const lines = content.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);

  if (lines.length < 9) {
    throw new Error(`palace-inscribe bridge: expected ≥9 lines in bundle, got ${lines.length}`);
  }

  const NULL_FP = '0'.repeat(64);
  const mythosPresent = lines[7] === '1';
  const archiformPresent = lines[8] === '1';

  return {
    palaceFp: lines[0],
    roomFp: lines[1],
    inscriptionFp: lines[2],
    actionFp: lines[3],
    sourceBlake3: lines[4],
    mythosFp: mythosPresent && lines[5] !== NULL_FP ? lines[5] : null,
    archiformFp: archiformPresent && lines[6] !== NULL_FP ? lines[6] : null,
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  debugLog(
    'palace-inscribe-bridge-debug',
    `[${new Date().toISOString()}] stagingPath=${stagingPath} bundlePath=${bundlePath}\n`
  );

  const parsed = parseBundle(bundlePath);
  // Validate every fp before any Cypher interpolation.
  const palaceFp = sanitizeFp(parsed.palaceFp, 'palaceFp');
  const roomFp = sanitizeFp(parsed.roomFp, 'roomFp');
  const inscriptionFp = sanitizeFp(parsed.inscriptionFp, 'inscriptionFp');
  const actionFp = sanitizeFp(parsed.actionFp, 'actionFp');
  const sourceBlake3 = sanitizeFp(parsed.sourceBlake3, 'sourceBlake3');
  const mythosFp = parsed.mythosFp ? sanitizeFp(parsed.mythosFp, 'mythosFp') : null;
  const archiformFp = parsed.archiformFp ? sanitizeFp(parsed.archiformFp, 'archiformFp') : null;

  const dbPath = process.env.PALACE_DB_PATH ?? 'palace.db';
  const store = new ServerStore(dbPath);
  await store.open();

  try {
    // AC3: verify the room is contained by this palace
    const roomCheck = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'})-[:CONTAINS]->(r:Room {fp: '${roomFp}'}) RETURN r.fp AS fp`
    );
    if (roomCheck.length === 0) {
      process.stderr.write(`room not in palace: room '${roomFp}' not found in palace '${palaceFp}'\n`);
      process.exit(1);
    }

    // AC6 idempotency check: if inscription_fp already exists, skip (idempotent re-apply).
    // True cycle enforcement for inscriptions is at the Zig fp-derivation level (unique per ns).
    const inscCheck = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${inscriptionFp}'}) RETURN i.fp AS fp`
    );
    if (inscCheck.length > 0) {
      console.log(`palace-inscribe bridge: inscription '${inscriptionFp}' already exists — idempotent skip`);
      return;
    }

    // 1. Inscribe avatar (creates Inscription node + Room→Inscription CONTAINS edge + LIVES_IN edge)
    await store.inscribeAvatar(roomFp, inscriptionFp, sourceBlake3, {
      archiform: archiformFp ?? undefined,
    });

    // 2. AC8: lazy aqueduct between palace and room on inscribe (FR18 CLI half)
    //    Creates Aqueduct node with D3 defaults if not already present.
    let aqueductFp: string | null = null;
    let aqueductCreated = false;

    try {
      const existingAq = await store.__rawQuery(
        `MATCH (a:Aqueduct {from_fp: '${palaceFp}', to_fp: '${roomFp}'}) RETURN a.fp AS fp`
      );
      if (existingAq.length === 0) {
        aqueductFp = await store.getOrCreateAqueduct(palaceFp, roomFp, palaceFp);
        aqueductCreated = true;
      } else {
        aqueductFp = String((existingAq[0] as { fp: string }).fp);
      }
    } catch (aqErr) {
      // Aqueduct creation is best-effort; do not fail the whole inscription
      console.warn(`palace-inscribe bridge: aqueduct creation warning: ${aqErr}`);
    }

    // 3. Optional Mythos node for the inscription
    if (mythosFp) {
      const mExists = await store.__rawQuery(
        `MATCH (m:Mythos {fp: '${mythosFp}'}) RETURN m.fp AS fp`
      );
      if (mExists.length === 0) {
        await store.__rawQuery(
          `CREATE (:Mythos {
            fp: '${mythosFp}',
            body: '',
            canonicality: 'genesis',
            discovered_in_action_fp: '${actionFp}',
            created_at: ${Date.now()}
          })`
        );
      }
      // Note: Inscription table does not have a mythos_fp column in schema.cypher.
      // The Mythos node is created above; association is via ActionLog/action_fp reference.
    }

    // 3b. S4.3: Mirror inscription triple into oracle knowledge-graph (AC1)
    //     Resolve oracle agent fp from PALACE_ORACLE_FP env or Agent node in DB.
    //     The triple (inscriptionFp, "lives-in", roomFp) is written via domain verb
    //     so it is part of the same write sequence as inscribeAvatar + mirrorAction (AC1).
    //     AC4 fault-injection contract: if this throws, the caller catches and rolls back.
    const oracleAgentFpRaw = process.env.PALACE_ORACLE_FP ?? '';
    if (oracleAgentFpRaw) {
      const oracleAgentFp = sanitizeFp(oracleAgentFpRaw, 'PALACE_ORACLE_FP');
      await mirrorInscriptionToKnowledgeGraph(store, {
        oracleAgentFp,
        docFp: inscriptionFp,
        roomFp,
      });
    }

    // 4. Mirror the avatar-inscribed action into ActionLog
    //    Convention: actor_fp = roomFp, target_fp = inscriptionFp (per action-mirror.ts)
    const now = Date.now();
    const action: MirrorAction = {
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'avatar-inscribed',
      actor_fp: roomFp, // convention from S2.2/action-mirror.ts
      target_fp: inscriptionFp,
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: sourceBlake3, // TC13: use source blake3 as content fingerprint
    };

    const exec = (cypher: string) => store.__rawQuery(cypher);
    await mirrorAction(exec, action);

    // 5. If aqueduct was newly created, mirror the aqueduct-created action (AC8).
    // The action fp is derived deterministically from (aqueductFp, 'aqueduct-created',
    // palaceFp, actionFp) — reusing deriveTripleFp as a generic 4-tuple blake3 so
    // replay reproduces the same ActionLog row.
    if (aqueductCreated && aqueductFp) {
      const validatedAqFp = sanitizeFp(aqueductFp, 'aqueductFp');
      const aqActionFp = await deriveTripleFp(
        validatedAqFp,
        'aqueduct-created',
        palaceFp,
        actionFp
      );
      const aqAction: MirrorAction = {
        fp: aqActionFp,
        palace_fp: palaceFp,
        action_kind: 'aqueduct-created',
        actor_fp: palaceFp,
        target_fp: validatedAqFp,
        parent_hashes: [actionFp],
        timestamp: now,
        cbor_bytes_blake3: validatedAqFp,
        extra: {
          fromFp: palaceFp,
          toFp: roomFp,
        },
      };
      await mirrorAction(exec, aqAction);
    }

    console.log(
      `palace-inscribe bridge: inscribed ${inscriptionFp} in room ${roomFp} (palace ${palaceFp})`
    );
  } finally {
    await store.close();
  }
}

main().catch((err) => {
  const errMsg = `palace-inscribe bridge error: ${err}\n${(err as Error)?.stack ?? ''}\n`;
  console.error(errMsg);
  debugLog('palace-inscribe-bridge-error', errMsg);
  process.exit(1);
});
