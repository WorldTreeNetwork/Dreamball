/**
 * POST /dreamballs — Mint a new DreamBall.
 *
 * The secret key is returned ONLY on this initial creation response.
 * Every subsequent GET on this fingerprint must never return secret_key_b58.
 *
 * Contract with the WASM module:
 *   - `mintDreamBall(type_id, name_ptr, name_len, created)` returns a packed
 *     u64 whose upper 32 bits are the pointer and lower 32 are the length
 *     of the RAW CBOR envelope bytes in linear memory.
 *   - The 64-byte Ed25519 secret lands in a separate buffer readable via
 *     `lastSecretPtr()` / `lastSecretLen()`.
 *   - To produce a JSON view of the envelope, we feed the CBOR bytes back
 *     through `parseJelly`.
 */

import Elysia, { t } from 'elysia';
import {
  getWasm,
  readPackedBytes,
  readLastSecret,
  parseEnvelopeToJson,
  writeString,
  base58Encode
} from '../wasm.js';
import { storeDreamBall, storeSecretKey } from '../store.js';

// type_id mapping matches wasm_main.zig#typeIdToEnum:
//   0=avatar 1=agent 2=tool 3=relic 4=field 5=guild 6=untyped (v1)
const TYPE_IDS: Record<string, number> = {
  avatar: 0,
  agent: 1,
  tool: 2,
  relic: 3,
  field: 4,
  guild: 5,
  untyped: 6
};

export const mintRoute = new Elysia().post(
  '/dreamballs',
  async ({ body }) => {
    const { type, name } = body;
    const typeId = TYPE_IDS[type];
    if (typeId === undefined) {
      throw new Error(`mint: unknown type "${type}"`);
    }
    const nowSecs = BigInt(Math.floor(Date.now() / 1000));

    const wasm = await getWasm();
    wasm.reset();

    let namePtr = 0;
    let nameLen = 0;
    if (name) {
      [namePtr, nameLen] = writeString(wasm, name);
    }

    // Mint — returns raw CBOR envelope bytes.
    const packed = wasm.mintDreamBall(typeId, namePtr, nameLen, nowSecs);
    const envelopeBytes = readPackedBytes(wasm, packed);
    const secretBytes = readLastSecret(wasm);
    const secretKeyB58 = `b58:${base58Encode(secretBytes)}`;

    // Parse envelope → JSON for the response body.
    wasm.reset();
    const dreamball = parseEnvelopeToJson(wasm, envelopeBytes);

    // Persist the raw CBOR bytes (content-addressed by fingerprint).
    const fingerprint = storeDreamBall(envelopeBytes, dreamball);
    storeSecretKey(fingerprint, secretBytes);

    const created_at =
      typeof dreamball['created'] === 'string'
        ? dreamball['created']
        : new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

    // secret_key_b58 is returned HERE only — never on subsequent reads.
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
