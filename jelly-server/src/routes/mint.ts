/**
 * POST /dreamballs — Mint a new DreamBall.
 *
 * The secret key is returned ONLY on this initial creation response.
 * Every subsequent GET on this fingerprint must never return secret_key_b58.
 */

import Elysia, { t } from 'elysia';
import { getWasm, readPackedString, writeString } from '../wasm.js';
import { storeDreamBall, storeSecretKey } from '../store.js';

const TYPE_IDS: Record<string, number> = {
  avatar: 1,
  agent: 2,
  tool: 3,
  relic: 4,
  field: 5,
  guild: 6,
  untyped: 0
};

export const mintRoute = new Elysia().post(
  '/dreamballs',
  async ({ body }) => {
    const { type, name } = body;
    const typeId = TYPE_IDS[type] ?? 0;
    const nowSecs = BigInt(Math.floor(Date.now() / 1000));

    const wasm = await getWasm();
    wasm.reset();

    let namePtr = 0;
    let nameLen = 0;
    if (name) {
      [namePtr, nameLen] = writeString(wasm, name);
    }

    const packed = wasm.mintDreamBall(typeId, namePtr, nameLen, nowSecs);
    const resultJson = readPackedString(wasm, packed);

    // mintDreamBall returns { dreamball_json: "...", secret_key_b58: "..." }
    const mintResult = JSON.parse(resultJson) as { dreamball_json: string; secret_key_b58: string };
    const dreamball = JSON.parse(mintResult.dreamball_json) as Record<string, unknown>;
    const secretKeyB58 = mintResult.secret_key_b58;

    const fingerprint = storeDreamBall(dreamball);
    storeSecretKey(fingerprint, secretKeyB58);

    const created_at = typeof dreamball['created'] === 'string'
      ? dreamball['created']
      : new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

    // secret_key_b58 is returned HERE only — never on subsequent reads
    return {
      fingerprint,
      dreamball,
      secret_key_b58: secretKeyB58,
      created_at
    };
  },
  {
    body: t.Object({
      type: t.Union([
        t.Literal('avatar'),
        t.Literal('agent'),
        t.Literal('tool'),
        t.Literal('relic'),
        t.Literal('field'),
        t.Literal('guild'),
        t.Literal('untyped')
      ]),
      name: t.Optional(t.String())
    }),
    detail: {
      summary: 'Mint a new DreamBall',
      description: 'Creates a new typed DreamBall. Returns the secret key ONCE — store it securely.'
    }
  }
);
