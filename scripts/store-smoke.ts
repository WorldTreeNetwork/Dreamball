/**
 * store-smoke.ts — AC8 store round-trip smoke test
 *
 * Exercises: open → ensurePalace → addRoom → inscribeAvatar → close →
 *            reopen → verify data persists → close
 *
 * Invoked from scripts/server-smoke.sh for the AC8 "store round-trip block".
 * Exit 0 = pass, exit 1 = fail.
 *
 * Uses a temp directory that is cleaned up on exit.
 *
 * Note: all fps must be 64-char lowercase hex (sanitizeFp constraint).
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { ServerStore } from '../src/memory-palace/store.server.js';

const PASS: string[] = [];
const FAIL: string[] = [];

function pass(label: string): void {
  console.log(`  PASS  ${label}`);
  PASS.push(label);
}

function fail(label: string, detail: string): void {
  console.error(`  FAIL  ${label}: ${detail}`);
  FAIL.push(label);
}

// Valid 64-char hex fps for all store operations
const PALACE_FP  = 'aa00000000000000aa00000000000000aa00000000000000aa00000000000000';
const ROOM_FP    = 'bb00000000000000bb00000000000000bb00000000000000bb00000000000000';
const INS_FP     = 'cc00000000000000cc00000000000000cc00000000000000cc00000000000000';
const SRC_FP     = 'dd00000000000000dd00000000000000dd00000000000000dd00000000000000';
const ACTION_FP  = 'ee00000000000000ee00000000000000ee00000000000000ee00000000000000';
const ACTOR_FP   = 'ff00000000000000ff00000000000000ff00000000000000ff00000000000000';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-ac8-'));
const dbPath = path.join(dir, 'palace.lbug');

try {
  // ── Phase 1: open, populate, close ─────────────────────────────────────────
  {
    const store = new ServerStore(dbPath);
    await store.open();

    await store.ensurePalace(PALACE_FP);
    await store.addRoom(PALACE_FP, ROOM_FP, { name: 'Smoke Room 1' });
    await store.inscribeAvatar(ROOM_FP, INS_FP, SRC_FP);
    await store.recordAction({
      fp: ACTION_FP,
      palaceFp: PALACE_FP,
      actionKind: 'palace-minted',
      actorFp: ACTOR_FP,
      parentHashes: [],
      timestamp: new Date()
    });
    await store.close();

    pass('Phase 1: open → ensurePalace → addRoom → inscribeAvatar → close');
  }

  // ── Phase 2: reopen, verify data persists ──────────────────────────────────
  {
    const store2 = new ServerStore(dbPath);
    await store2.open();

    const palaceRows = await store2.__rawQuery<{ fp: string }>(
      `MATCH (p:Palace {fp: '${PALACE_FP}'}) RETURN p.fp AS fp`
    );
    if (palaceRows.length === 1 && String(palaceRows[0].fp) === PALACE_FP) {
      pass('Phase 2: Palace persists after reopen');
    } else {
      fail('Phase 2: Palace persists after reopen', `got ${JSON.stringify(palaceRows)}`);
    }

    const chainRows = await store2.__rawQuery<{ cnt: number }>(
      `MATCH (:Palace {fp: '${PALACE_FP}'})-[:CONTAINS]->(:Room)-[:CONTAINS]->(:Inscription)
       RETURN count(*) AS cnt`
    );
    const cnt = Number(chainRows[0]?.cnt ?? -1);
    if (cnt === 1) {
      pass('Phase 2: Palace→Room→Inscription chain intact after reopen');
    } else {
      fail('Phase 2: Palace→Room→Inscription chain intact after reopen', `count = ${cnt}`);
    }

    const actionRows = await store2.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {fp: '${ACTION_FP}'}) RETURN a.fp AS fp`
    );
    if (actionRows.length === 1) {
      pass('Phase 2: ActionLog row persists after reopen');
    } else {
      fail('Phase 2: ActionLog row persists after reopen', `got ${JSON.stringify(actionRows)}`);
    }

    const heads = await store2.headHashes(PALACE_FP);
    if (heads.includes(ACTION_FP)) {
      pass('Phase 2: headHashes returns action fp after reopen');
    } else {
      fail('Phase 2: headHashes returns action fp after reopen', `heads = ${JSON.stringify(heads)}`);
    }

    await store2.close();
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log(`\n  Store smoke: ${PASS.length} passed, ${FAIL.length} failed`);
if (FAIL.length > 0) {
  process.exit(1);
}
process.exit(0);
