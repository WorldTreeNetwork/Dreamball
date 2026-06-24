/**
 * GET /dreamballs/:fp/verify — Verify Ed25519 signature on a stored DreamBall.
 */

import Elysia, { t } from 'elysia';
import { loadDreamBall } from '../store.js';
import { getWasm } from '../wasm.js';

export const verifyRoute = new Elysia().get(
  '/dreamballs/:fp/verify',
  async ({ params, set }) => {
    const db = loadDreamBall(params.fp);
    if (!db) {
      set.status = 404;
      return { error: 'not found', fingerprint: params.fp };
    }

    const wasm = await getWasm();
    wasm.reset();

    const jsonBytes = new TextEncoder().encode(JSON.stringify(db));
    const ptr = wasm.alloc(jsonBytes.length);
    if (ptr === 0) {
      return { ok: false, hadEd25519: false, reason: 'wasm alloc failed' };
    }
    new Uint8Array(wasm.memory.buffer, ptr, jsonBytes.length).set(jsonBytes);

    const result = wasm.verifyJelly(ptr, jsonBytes.length);

    if (result === 2) return { ok: true, hadEd25519: true };
    if (result === 1) return { ok: true, hadEd25519: false };

    const ep = wasm.resultErrPtr();
    const el = wasm.resultErrLen();
    const reason = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, ep, el));
    return { ok: false, hadEd25519: false, reason: reason || 'signature verification failed' };
  },
  {
    params: t.Object({ fp: t.String() }),
    detail: {
      summary: 'Verify DreamBall signature',
      description: 'Returns { ok, hadEd25519, reason? }. ok=true means Ed25519 verified or no signature present.'
    }
  }
);
