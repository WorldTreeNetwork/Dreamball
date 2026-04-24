/**
 * palace-move.ts — Bridge script invoked by `jelly palace move` (Zig → Bun).
 *
 * Argv: <staging_path> <bundle_path>
 *
 * Bundle format (one value per line):
 *   Line 0: palace_fp (64 hex)
 *   Line 1: avatar_fp (64 hex) — inscription to move
 *   Line 2: to_room_fp (64 hex) — destination room
 *   Line 3: action_fp (64 hex) — signed move action fp
 *
 * Responsibility (D-008 4-step sequence):
 *   1. Verify avatar exists and currently has a LIVES_IN edge (find from_room_fp)
 *   2. Verify to_room_fp exists in this palace
 *   3. Delete old LIVES_IN edge, create new LIVES_IN edge
 *   4. Mirror move into oracle knowledge_graph via mirrorInscriptionMove
 *   5. Mirror move action into ActionLog via mirrorAction
 *
 * SEC11: Zig signs action before bridge runs. Bridge only writes DB rows.
 * AC2: move updates oracle KG triple + LIVES_IN + ActionLog.
 * D-007: triple write routes through store.updateTriple (via mirrorInscriptionMove).
 */

import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ServerStore } from '../../memory-palace/store.server.js';
import { mirrorAction, type MirrorAction } from '../../memory-palace/action-mirror.js';
import { mirrorInscriptionMove } from '../../memory-palace/oracle.js';
import { sanitizeFp } from '../../memory-palace/cypher-utils.js';

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
  console.error('palace-move bridge: usage: <staging_path> <bundle_path>');
  process.exit(1);
}

// ── Bundle parsing ────────────────────────────────────────────────────────────

interface MoveBundle {
  palaceFp: string;
  avatarFp: string;
  toRoomFp: string;
  actionFp: string;
}

function parseBundle(path: string): MoveBundle {
  const content = readFileSync(path, 'utf-8');
  const lines = content.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);

  if (lines.length < 4) {
    throw new Error(`palace-move bridge: expected ≥4 lines in bundle, got ${lines.length}`);
  }

  return {
    palaceFp: lines[0],
    avatarFp: lines[1],
    toRoomFp: lines[2],
    actionFp: lines[3],
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  debugLog(
    'palace-move-bridge-debug',
    `[${new Date().toISOString()}] stagingPath=${stagingPath} bundlePath=${bundlePath}\n`
  );

  const parsed = parseBundle(bundlePath);
  const palaceFp = sanitizeFp(parsed.palaceFp, 'palaceFp');
  const avatarFp = sanitizeFp(parsed.avatarFp, 'avatarFp');
  const toRoomFp = sanitizeFp(parsed.toRoomFp, 'toRoomFp');
  const actionFp = sanitizeFp(parsed.actionFp, 'actionFp');

  const dbPath = process.env.PALACE_DB_PATH ?? 'palace.db';
  const store = new ServerStore(dbPath);
  await store.open();

  try {
    // 1. Verify avatar exists and find current LIVES_IN room
    const avatarCheck = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${avatarFp}'})-[:LIVES_IN]->(r:Room) RETURN r.fp AS fromRoomFp`
    );
    if (avatarCheck.length === 0) {
      process.stderr.write(
        `palace-move bridge: avatar '${avatarFp}' not found or has no LIVES_IN edge\n`
      );
      process.exit(1);
    }
    const fromRoomFp = sanitizeFp(
      String((avatarCheck[0] as { fromRoomFp: string }).fromRoomFp),
      'fromRoomFp'
    );

    // 2. Verify destination room exists in this palace
    const toRoomCheck = await store.__rawQuery(
      `MATCH (p:Palace {fp: '${palaceFp}'})-[:CONTAINS]->(r:Room {fp: '${toRoomFp}'}) RETURN r.fp AS fp`
    );
    if (toRoomCheck.length === 0) {
      process.stderr.write(
        `palace-move bridge: destination room '${toRoomFp}' not found in palace '${palaceFp}'\n`
      );
      process.exit(1);
    }

    // 3. If already in destination room, skip (idempotent)
    if (fromRoomFp === toRoomFp) {
      console.log(
        `palace-move bridge: avatar '${avatarFp}' already in room '${toRoomFp}' — idempotent skip`
      );
      return;
    }

    // 4. Update LIVES_IN edge: delete old, create new
    await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${avatarFp}'})-[e:LIVES_IN]->(r:Room {fp: '${fromRoomFp}'}) DELETE e`
    );
    await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${avatarFp}'})
       MATCH (r:Room {fp: '${toRoomFp}'})
       CREATE (i)-[:LIVES_IN]->(r)`
    );

    // 5. Mirror move into oracle knowledge_graph (via domain verb — D-007 / AC7)
    const oracleAgentFpRaw = process.env.PALACE_ORACLE_FP ?? '';
    if (oracleAgentFpRaw) {
      const oracleAgentFp = sanitizeFp(oracleAgentFpRaw, 'PALACE_ORACLE_FP');
      await mirrorInscriptionMove(store, {
        oracleAgentFp,
        docFp: avatarFp,
        fromRoomFp,
        toRoomFp,
      });
    }

    // 6. Mirror move action into ActionLog
    const now = Date.now();
    const action: MirrorAction = {
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'move',
      actor_fp: fromRoomFp,
      target_fp: avatarFp,
      parent_hashes: [],
      timestamp: now,
      extra: {
        fromFp: fromRoomFp,
        toFp: toRoomFp,
      },
    };

    const exec = (cypher: string) => store.__rawQuery(cypher);
    await mirrorAction(exec, action, store);

    console.log(
      `palace-move bridge: moved ${avatarFp} from ${fromRoomFp} to ${toRoomFp} (palace ${palaceFp})`
    );
  } finally {
    await store.close();
  }
}

main().catch((err) => {
  const errMsg = `palace-move bridge error: ${err}\n${(err as Error)?.stack ?? ''}\n`;
  console.error(errMsg);
  debugLog('palace-move-bridge-error', errMsg);
  process.exit(1);
});
