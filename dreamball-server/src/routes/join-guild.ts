/**
 * POST /dreamballs/:fp/join-guild — Add a guild membership to a DreamBall
 * and re-sign. Requires the DreamBall's secret key.
 *
 * Contract with wasm_main.zig#joinGuildWasm:
 *   joinGuildWasm(envPtr, envLen, guildEnvPtr, guildEnvLen,
 *                 secretPtr, secretLen, updated)
 *                 -> packed u64 (new envelope bytes)
 */

import Elysia, { t } from 'elysia';
import { loadEnvelopeBytes, storeDreamBall } from '../store.js';
import {
  getWasm,
  readPackedBytes,
  parseEnvelopeToJson,
  writeBytes,
  base58Decode
} from '../wasm.js';

export const joinGuildRoute = new Elysia().post(
  '/dreamballs/:fp/join-guild',
  async ({ params, body, set }) => {
    const envBytes = loadEnvelopeBytes(params.fp);
    if (!envBytes) {
      set.status = 404;
      return { error: 'dreamball not found', fingerprint: params.fp };
    }

    const guildBytes = loadEnvelopeBytes(body.guild_fp);
    if (!guildBytes) {
      set.status = 404;
      return { error: 'guild not found', fingerprint: body.guild_fp };
    }

    const secretBytes = base58Decode(body.secret_key_b58);
    if (secretBytes.length !== 64) {
      set.status = 400;
      return { error: 'secret_key_b58 must decode to 64 bytes' };
    }

    const wasm = await getWasm();
    wasm.reset();

    const [envPtr, envLen] = writeBytes(wasm, envBytes);
    const [guildPtr, guildLen] = writeBytes(wasm, guildBytes);
    const [secretPtr, secretLen] = writeBytes(wasm, secretBytes);

    const updatedSecs = BigInt(Math.floor(Date.now() / 1000));
    const packed = wasm.joinGuildWasm(
      envPtr,
      envLen,
      guildPtr,
      guildLen,
      secretPtr,
      secretLen,
      updatedSecs
    );
    const newEnvelopeBytes = readPackedBytes(wasm, packed);

    wasm.reset();
    const updated = parseEnvelopeToJson(wasm, newEnvelopeBytes);
    storeDreamBall(newEnvelopeBytes, updated);

    const safe = { ...updated };
    delete (safe as Record<string, unknown>)['secret_key_b58'];
    return safe;
  },
  {
    params: t.Object({ fp: t.String() }),
    body: t.Object({
      guild_fp: t.String(),
      secret_key_b58: t.String()
    }),
    detail: {
      summary: 'Join a Guild',
      description:
        'Appends a Guild membership assertion to the DreamBall and re-signs. Requires the secret key.'
    }
  }
);
