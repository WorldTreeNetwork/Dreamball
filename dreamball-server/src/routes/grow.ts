/**
 * POST /dreamballs/:fp/grow — Apply updates to an existing DreamBall and
 * re-sign. Requires the caller to present the 64-byte Ed25519 secret
 * (base58-encoded) — the server never returns secrets after mint.
 *
 * Contract with wasm_main.zig#growDreamBall:
 *   growDreamBall(envPtr, envLen, secretPtr, secretLen,
 *                 newNamePtr, newNameLen, updated, promoteToDreamball)
 *                 -> packed u64 (new envelope bytes)
 */

import Elysia, { t } from 'elysia';
import { loadEnvelopeBytes, storeDreamBall } from '../store.js';
import {
  getWasm,
  readPackedBytes,
  parseEnvelopeToJson,
  writeString,
  writeBytes,
  base58Decode
} from '../wasm.js';

export const growRoute = new Elysia().post(
  '/dreamballs/:fp/grow',
  async ({ params, body, set }) => {
    const envBytes = loadEnvelopeBytes(params.fp);
    if (!envBytes) {
      set.status = 404;
      return { error: 'not found', fingerprint: params.fp };
    }

    const { secret_key_b58, updates } = body;
    const secretBytes = base58Decode(secret_key_b58);
    if (secretBytes.length !== 64) {
      set.status = 400;
      return { error: 'secret_key_b58 must decode to 64 bytes' };
    }

    const wasm = await getWasm();
    wasm.reset();

    const [envPtr, envLen] = writeBytes(wasm, envBytes);
    const [secretPtr, secretLen] = writeBytes(wasm, secretBytes);

    let newNamePtr = 0;
    let newNameLen = 0;
    if (updates.name) {
      [newNamePtr, newNameLen] = writeString(wasm, updates.name);
    }

    const updatedSecs = BigInt(Math.floor(Date.now() / 1000));
    const promoteFlag = updates.promote_to_dreamball ? 1 : 0;

    const packed = wasm.growDreamBall(
      envPtr,
      envLen,
      secretPtr,
      secretLen,
      newNamePtr,
      newNameLen,
      updatedSecs,
      promoteFlag
    );
    const newEnvelopeBytes = readPackedBytes(wasm, packed);

    wasm.reset();
    const updated = parseEnvelopeToJson(wasm, newEnvelopeBytes);
    storeDreamBall(newEnvelopeBytes, updated);

    // Explicit guard: never return secret_key_b58
    const safe = { ...updated };
    delete (safe as Record<string, unknown>)['secret_key_b58'];
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
      description:
        'Applies updates, bumps revision, re-signs. Requires the secret key. Does not return secret key.'
    }
  }
);
