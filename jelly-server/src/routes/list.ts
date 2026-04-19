/**
 * GET /dreamballs — List all stored DreamBalls.
 * Returns fingerprint + summary (name, type, stage). Never returns secret keys.
 */

import Elysia from 'elysia';
import { listDreamBalls } from '../store.js';

export const listRoute = new Elysia().get(
  '/dreamballs',
  () => {
    const all = listDreamBalls();
    return all.map(({ fingerprint, dreamball }) => {
      // Explicit guard: strip secret_key_b58 from any record
      const { secret_key_b58: _stripped, ...safe } = dreamball as Record<string, unknown> & { secret_key_b58?: string };
      void _stripped;
      return {
        fingerprint,
        summary: {
          type: safe['type'],
          name: safe['name'],
          stage: safe['stage'],
          identity: safe['identity'],
          revision: safe['revision'],
          created: safe['created']
        }
      };
    });
  },
  {
    detail: {
      summary: 'List all DreamBalls',
      description: 'Returns an array of { fingerprint, summary } objects. No secret keys.'
    }
  }
);
