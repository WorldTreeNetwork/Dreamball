/**
 * POST /relics — Seal a DreamBall into a relic.
 * MVP: subprocesses to `jelly seal-relic` CLI.
 */

import Elysia, { t } from 'elysia';
import { spawnSync } from 'child_process';
import { resolve } from 'path';
import { writeFileSync, readFileSync, unlinkSync, existsSync } from 'fs';
import { storeDreamBall } from '../store.js';
import { randomBytes } from 'crypto';
import { moduleDir } from '../paths.js';

const REPO_ROOT = resolve(moduleDir(import.meta.url, import.meta.dir), '../../../');
const JELLY = process.env.JELLY_CLI ?? resolve(REPO_ROOT, 'zig-out/bin/jelly');

export const sealRelicRoute = new Elysia().post(
  '/relics',
  async ({ body, set }) => {
    const { inner_dreamball_json, unlock_guild_fp, reveal_hint } = body;

    if (!existsSync(JELLY)) {
      set.status = 503;
      return { error: 'jelly CLI not found; run `zig build` first', path: JELLY };
    }

    // Write inner DreamBall to a temp file
    const tmpId = randomBytes(8).toString('hex');
    const innerPath = `/tmp/jelly-inner-${tmpId}.jelly`;
    const outPath = `/tmp/jelly-relic-${tmpId}.jelly`;

    try {
      writeFileSync(innerPath, inner_dreamball_json, 'utf-8');

      const args = ['seal-relic', innerPath, '--for-guild', unlock_guild_fp, '--out', outPath];
      if (reveal_hint) args.push('--hint', reveal_hint);

      const res = spawnSync(JELLY, args, { encoding: 'utf-8' });
      if (res.status !== 0) {
        set.status = 422;
        return { error: res.stderr?.trim() || 'seal-relic failed', code: res.status };
      }

      if (!existsSync(outPath)) {
        set.status = 500;
        return { error: 'seal-relic produced no output file' };
      }

      const relicJson = readFileSync(outPath, 'utf-8');
      const relic = JSON.parse(relicJson) as Record<string, unknown>;
      // seal-relic output is JSON (no raw CBOR available); pass JSON bytes as envelope bytes
      const fingerprint = storeDreamBall(new TextEncoder().encode(relicJson), relic);

      return { fingerprint, relic };
    } finally {
      try { unlinkSync(innerPath); } catch { /* ignore */ }
      try { unlinkSync(outPath); } catch { /* ignore */ }
    }
  },
  {
    body: t.Object({
      inner_dreamball_json: t.String(),
      unlock_guild_fp: t.String(),
      reveal_hint: t.Optional(t.String())
    }),
    detail: {
      summary: 'Seal a relic',
      description: 'Wraps an inner DreamBall JSON into a sealed Relic envelope. MVP: subprocesses to jelly CLI.'
    }
  }
);
