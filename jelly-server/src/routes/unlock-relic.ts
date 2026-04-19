/**
 * POST /relics/:id/unlock — Unlock a sealed relic and extract the inner DreamBall.
 * MVP: subprocesses to `jelly unlock` CLI.
 */

import Elysia, { t } from 'elysia';
import { spawnSync } from 'child_process';
import { resolve } from 'path';
import { writeFileSync, readFileSync, unlinkSync, existsSync } from 'fs';
import { loadDreamBall } from '../store.js';
import { randomBytes } from 'crypto';
import { moduleDir } from '../paths.js';

const REPO_ROOT = resolve(moduleDir(import.meta.url, import.meta.dir), '../../../');
const JELLY = process.env.JELLY_CLI ?? resolve(REPO_ROOT, 'zig-out/bin/jelly');

export const unlockRelicRoute = new Elysia().post(
  '/relics/:id/unlock',
  async ({ params, body, set }) => {
    const relic = loadDreamBall(params.id);
    if (!relic) {
      set.status = 404;
      return { error: 'relic not found', id: params.id };
    }

    if (!existsSync(JELLY)) {
      set.status = 503;
      return { error: 'jelly CLI not found; run `zig build` first', path: JELLY };
    }

    const tmpId = randomBytes(8).toString('hex');
    const relicPath = `/tmp/jelly-relic-${tmpId}.jelly`;
    const outPath = `/tmp/jelly-unlocked-${tmpId}.jelly`;

    try {
      writeFileSync(relicPath, JSON.stringify(relic), 'utf-8');

      const args = ['unlock', relicPath, '--out', outPath];

      const res = spawnSync(JELLY, args, { encoding: 'utf-8' });
      if (res.status !== 0) {
        set.status = 422;
        return { error: res.stderr?.trim() || 'unlock failed', code: res.status };
      }

      if (!existsSync(outPath)) {
        set.status = 500;
        return { error: 'unlock produced no output file' };
      }

      const innerJson = readFileSync(outPath, 'utf-8');
      const inner = JSON.parse(innerJson) as Record<string, unknown>;

      // Explicit guard: never return secret_key_b58
      const { secret_key_b58: _stripped, ...safe } = inner as Record<string, unknown> & { secret_key_b58?: string };
      void _stripped;
      return safe;
    } finally {
      try { unlinkSync(relicPath); } catch { /* ignore */ }
      try { unlinkSync(outPath); } catch { /* ignore */ }
    }
  },
  {
    params: t.Object({ id: t.String() }),
    body: t.Object({}),
    detail: {
      summary: 'Unlock a relic',
      description: 'Extracts the inner DreamBall from a sealed relic. MVP: subprocesses to jelly CLI.'
    }
  }
);
