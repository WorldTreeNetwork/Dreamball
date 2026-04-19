/**
 * POST /dreamballs/:fp/transmit — Transmit a Tool DreamBall to a target Agent via a Guild.
 * MVP: subprocesses to `jelly transmit` CLI.
 */

import Elysia, { t } from 'elysia';
import { spawnSync } from 'child_process';
import { resolve } from 'path';
import { writeFileSync, readFileSync, unlinkSync, existsSync } from 'fs';
import { loadDreamBall } from '../store.js';
import { randomBytes } from 'crypto';

const REPO_ROOT = resolve(import.meta.dir, '../../../');
const JELLY = process.env.JELLY_CLI ?? resolve(REPO_ROOT, 'zig-out/bin/jelly');

export const transmitRoute = new Elysia().post(
  '/dreamballs/:fp/transmit',
  async ({ params, body, set }) => {
    const tool = loadDreamBall(params.fp);
    if (!tool) {
      set.status = 404;
      return { error: 'tool DreamBall not found', fingerprint: params.fp };
    }

    if (!existsSync(JELLY)) {
      set.status = 503;
      return { error: 'jelly CLI not found; run `zig build` first', path: JELLY };
    }

    const tmpId = randomBytes(8).toString('hex');
    const toolPath = `/tmp/jelly-tool-${tmpId}.jelly`;
    const keyPath = `/tmp/jelly-key-${tmpId}.key`;
    const outPath = `/tmp/jelly-transmit-${tmpId}.jelly`;

    try {
      writeFileSync(toolPath, JSON.stringify(tool), 'utf-8');
      writeFileSync(keyPath, body.sender_key_b58, { encoding: 'utf-8', mode: 0o600 });

      const args = [
        'transmit', toolPath,
        '--to', body.to_fp,
        '--via-guild', body.via_guild_fp,
        '--sender-key', keyPath,
        '--out', outPath
      ];

      const res = spawnSync(JELLY, args, { encoding: 'utf-8' });
      if (res.status !== 0) {
        set.status = 422;
        return { error: res.stderr?.trim() || 'transmit failed', code: res.status };
      }

      if (!existsSync(outPath)) {
        set.status = 500;
        return { error: 'transmit produced no output file' };
      }

      const receiptJson = readFileSync(outPath, 'utf-8');
      const receipt = JSON.parse(receiptJson) as Record<string, unknown>;

      // Explicit guard: never return secret_key_b58
      const { secret_key_b58: _stripped, ...safe } = receipt as Record<string, unknown> & { secret_key_b58?: string };
      void _stripped;
      return safe;
    } finally {
      try { unlinkSync(toolPath); } catch { /* ignore */ }
      try { unlinkSync(keyPath); } catch { /* ignore */ }
      try { unlinkSync(outPath); } catch { /* ignore */ }
    }
  },
  {
    params: t.Object({ fp: t.String() }),
    body: t.Object({
      to_fp: t.String(),
      via_guild_fp: t.String(),
      sender_key_b58: t.String()
    }),
    detail: {
      summary: 'Transmit a Tool DreamBall',
      description: 'Produces a signed transmission receipt. MVP: subprocesses to jelly CLI.'
    }
  }
);
