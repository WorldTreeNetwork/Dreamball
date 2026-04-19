/**
 * POST /dreamballs/:fp/grow — Apply updates to an existing DreamBall and re-sign.
 * Requires the secret_key_b58 for authorization.
 * Never returns secret_key_b58 in the response.
 */

import Elysia, { t } from 'elysia';
import { loadDreamBall, storeDreamBall } from '../store.js';
import { getWasm, readPackedString, writeString } from '../wasm.js';

export const growRoute = new Elysia().post(
  '/dreamballs/:fp/grow',
  async ({ params, body, set }) => {
    const db = loadDreamBall(params.fp);
    if (!db) {
      set.status = 404;
      return { error: 'not found', fingerprint: params.fp };
    }

    const { secret_key_b58, updates } = body;

    const wasm = await getWasm();
    wasm.reset();

    const input = JSON.stringify({
      dreamball_json: JSON.stringify(db),
      secret_key_b58,
      updates
    });

    const [ptr, len] = writeString(wasm, input);
    const packed = wasm.growDreamBall(ptr, len);
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
      secret_key_b58: t.String(),
      updates: t.Object({
        name: t.Optional(t.String()),
        promote_to_dreamball: t.Optional(t.Boolean())
      })
    }),
    detail: {
      summary: 'Grow (update) a DreamBall',
      description: 'Applies updates, bumps revision, re-signs. Requires the secret key. Does not return secret key.'
    }
  }
);
