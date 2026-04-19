/**
 * GET /dreamballs/:fp — Return a DreamBall by fingerprint.
 * Never returns secret_key_b58.
 */

import Elysia, { t } from 'elysia';
import { loadDreamBall } from '../store.js';

export const showRoute = new Elysia().get(
  '/dreamballs/:fp',
  ({ params, set }) => {
    const db = loadDreamBall(params.fp);
    if (!db) {
      set.status = 404;
      return { error: 'not found', fingerprint: params.fp };
    }
    // Explicit guard: strip secret_key_b58 even if somehow present in stored data
    const { secret_key_b58: _stripped, ...safe } = db as Record<string, unknown> & { secret_key_b58?: string };
    void _stripped;
    return safe;
  },
  {
    params: t.Object({ fp: t.String() }),
    detail: {
      summary: 'Get a DreamBall',
      description: 'Returns the stored DreamBall JSON. Never includes secret_key_b58.'
    }
  }
);
