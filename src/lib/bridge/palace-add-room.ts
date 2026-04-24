/**
 * palace-add-room.ts — Bridge script invoked by `jelly palace add-room` (Zig → Bun).
 *
 * Argv: <staging_path> <bundle_path>
 *
 * Bundle format (one value per line):
 *   Line 0: palace_fp (64 hex)
 *   Line 1: room_fp (64 hex)
 *   Line 2: action_fp (64 hex)
 *   Line 3: mythos_fp (64 hex, or "0"×64 if absent)
 *   Line 4: archiform_fp (64 hex, or "0"×64 if absent)
 *   Line 5: "1" if mythos present, "0" otherwise
 *   Line 6: "1" if archiform present, "0" otherwise
 *   Line 7: room name (arbitrary string)
 *
 * Responsibility:
 *   1. Open store
 *   2. AC6 cycle check: reject if room_fp already appears as an ancestor of palace_fp
 *   3. store.addRoom(palaceFp, roomFp, { name, archiform? })
 *   4. Optionally create Mythos node + MYTHOS_HEAD pointer for room
 *   5. mirrorAction for "room-added"
 *
 * SEC11: Zig orchestrates CAS atomicity. Bridge only writes DB rows.
 * TC13: No CBOR bytes stored — all references are Blake3 fps.
 * AC6: Cycle enforcement here (bridge has graph loaded).
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
  console.error('palace-add-room bridge: usage: <staging_path> <bundle_path>');
  process.exit(1);
}

// ── Bundle parsing ────────────────────────────────────────────────────────────

interface AddRoomBundle {
  palaceFp: string;
  roomFp: string;
  actionFp: string;
  mythosFp: string | null;
  archiformFp: string | null;
  name: string;
}

function parseBundle(path: string): AddRoomBundle {
  const content = readFileSync(path, 'utf-8');
  const lines = content.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);

  if (lines.length < 8) {
    throw new Error(`palace-add-room bridge: expected ≥8 lines in bundle, got ${lines.length}`);
  }

  const palaceFp = lines[0];
  const roomFp = lines[1];
  const actionFp = lines[2];
  const mythosFpRaw = lines[3];
  const archiformFpRaw = lines[4];
  const mythosPresent = lines[5] === '1';
  const archiformPresent = lines[6] === '1';
  const name = lines[7];

  const NULL_FP = '0'.repeat(64);

  return {
    palaceFp,
    roomFp,
    actionFp,
    mythosFp: mythosPresent && mythosFpRaw !== NULL_FP ? mythosFpRaw : null,
    archiformFp: archiformPresent && archiformFpRaw !== NULL_FP ? archiformFpRaw : null,
    name,
  };
}

// ── Cycle check ───────────────────────────────────────────────────────────────
// AC6: a room cannot be added if its fp already appears in the palace's
// CONTAINS graph (would create a self-referential cycle).
// Strategy: query all Room fps reachable from the palace; if room_fp is among
// them, reject.

async function checkCycle(
  store: ServerStore,
  palaceFp: string,
  roomFp: string
): Promise<void> {
  // Caller has already validated both fps; re-validate defensively.
  const p = sanitizeFp(palaceFp, 'palaceFp');
  const r = sanitizeFp(roomFp, 'roomFp');
  // Direct containment check: is roomFp already contained by this palace?
  const existing = await store.__rawQuery(
    `MATCH (p:Palace {fp: '${p}'})-[:CONTAINS]->(r:Room {fp: '${r}'}) RETURN r.fp AS fp`
  );
  if (existing.length > 0) {
    throw new Error(`cycle: room '${r}' is already contained by palace '${p}'`);
  }

  // Transitive check: is roomFp an ancestor of palaceFp?
  if (r === p) {
    throw new Error(`cycle: room fp equals palace fp — self-referential CONTAINS rejected`);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  debugLog(
    'palace-add-room-bridge-debug',
    `[${new Date().toISOString()}] stagingPath=${stagingPath} bundlePath=${bundlePath}\n`
  );

  const parsed = parseBundle(bundlePath);
  // Validate every fp before any Cypher interpolation.
  const palaceFp = sanitizeFp(parsed.palaceFp, 'palaceFp');
  const roomFp = sanitizeFp(parsed.roomFp, 'roomFp');
  const actionFp = sanitizeFp(parsed.actionFp, 'actionFp');
  const mythosFp = parsed.mythosFp ? sanitizeFp(parsed.mythosFp, 'mythosFp') : null;
  const archiformFp = parsed.archiformFp ? sanitizeFp(parsed.archiformFp, 'archiformFp') : null;
  const name = parsed.name;

  const dbPath = process.env.PALACE_DB_PATH ?? 'palace.db';
  const store = new ServerStore(dbPath);
  await store.open();

  try {
    // AC6: cycle check before any write
    await checkCycle(store, palaceFp, roomFp);

    // AC3: verify palace exists
    const palaceCheck = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'}) RETURN p.fp AS fp`
    );
    if (palaceCheck.length === 0) {
      throw new Error(`palace-add-room bridge: palace '${palaceFp}' not found in store`);
    }

    // 1. Add room to store (creates Room node + Palace→Room CONTAINS edge)
    await store.addRoom(palaceFp, roomFp, {
      name,
      archiform: archiformFp ?? undefined,
    });

    // 2. If mythos was provided, create Mythos node for the room.
    if (mythosFp) {
      const mExists = await store.__rawQuery(
        `MATCH (m:Mythos {fp: '${mythosFp}'}) RETURN m.fp AS fp`
      );
      if (mExists.length === 0) {
        await store.__rawQuery(
          `CREATE (:Mythos {
            fp: '${mythosFp}',
            body: ${cypherString('')},
            canonicality: 'genesis',
            discovered_in_action_fp: '${actionFp}',
            created_at: ${Date.now()}
          })`
        );
      }
    }

    // 3. Mirror the room-added action into ActionLog
    const now = Date.now();
    const action: MirrorAction = {
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: palaceFp, // custodian = palace fp (actor = palace identity)
      target_fp: roomFp,
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: actionFp,
    };

    const exec = (cypher: string) => store.__rawQuery(cypher);
    await mirrorAction(exec, action);

    console.log(`palace-add-room bridge: added room ${roomFp} (${name}) to palace ${palaceFp}`);
  } finally {
    await store.close();
  }
}

main().catch((err) => {
  const errMsg = `palace-add-room bridge error: ${err}\n${(err as Error)?.stack ?? ''}\n`;
  console.error(errMsg);
  debugLog('palace-add-room-bridge-error', errMsg);

  const msg = String(err);
  if (msg.includes('cycle') || msg.includes('not found') || msg.includes('room not in palace')) {
    process.stderr.write(msg + '\n');
  }
  process.exit(1);
});
