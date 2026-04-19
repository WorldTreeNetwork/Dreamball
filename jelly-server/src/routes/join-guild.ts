/**
 * POST /dreamballs/:fp/join-guild — Add a guild membership to a DreamBall and re-sign.
 */

import Elysia, { t } from 'elysia';
import { loadDreamBall, storeDreamBall } from '../store.js';
import { getWasm, readPackedString, writeString } from '../wasm.js';

export const joinGuildRoute = new Elysia().post(
  '/dreamballs/:fp/join-guild',
  async ({ params, body, set }) => {
    const db = loadDreamBall(params.fp);
    if (!db) {
      set.status = 404;
      return { error: 'not found', fingerprint: params.fp };
    }

    // Load the guild to get its identity
    const guild = loadDreamBall(body.guild_fp);
    if (!guild) {
      set.status = 404;
      return { error: 'guild not found', fingerprint: body.guild_fp };
    }

    const { secret_key_b58 } = body;

    const wasm = await getWasm();
    wasm.reset();

    const input = JSON.stringify({
      dreamball_json: JSON.stringify(db),
      guild_json: JSON.stringify(guild),
      secret_key_b58
    });

    const [ptr, len] = writeString(wasm, input);
    const packed = wasm.joinGuildWasm(ptr, len);
    const resultJson = readPackedString(wasm, packed);

    const updated = JSON.parse(resultJson) as Record<string, unknown>;
    storeDreamBall(updated);

    // Explicit guard: never return secret_key_b58
    const { secret_key_b58: _stripped, ...safe } = updated as Record<string, unknown> & { secret_key_b58?: string };
    void _stripped;
    return safe;
  },
  {
    params: t.Object({ fp: t.String() }),
    body: t.Object({
      guild_fp: t.String(),
      secret_key_b58: t.String()
    }),
    detail: {
      summary: 'Join a guild',
      description: 'Appends a guild assertion to the DreamBall and re-signs. Requires the secret key.'
    }
  }
);
