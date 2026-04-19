/**
 * Singleton WASM instance loader for jelly-server.
 *
 * Reads jelly.wasm from disk once, instantiates with the host-provided
 * getRandomBytes import, and caches the instance for the lifetime of the
 * process. All routes share this one instance — callers must call reset()
 * before each operation to clear the linear memory scratch arena.
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';

export interface WasmExports {
  memory: WebAssembly.Memory;
  alloc: (size: number) => number;
  reset: () => void;
  parseJelly: (ptr: number, len: number) => bigint;
  verifyJelly: (ptr: number, len: number) => number;
  mintDreamBall: (typeId: number, namePtr: number, nameLen: number, created: bigint) => bigint;
  growDreamBall: (
    envPtr: number,
    envLen: number,
    secretPtr: number,
    secretLen: number,
    newNamePtr: number,
    newNameLen: number,
    updated: bigint,
    promoteToDreamball: number
  ) => bigint;
  joinGuildWasm: (
    envPtr: number,
    envLen: number,
    guildEnvPtr: number,
    guildEnvLen: number,
    secretPtr: number,
    secretLen: number,
    updated: bigint
  ) => bigint;
  lastSecretPtr: () => number;
  lastSecretLen: () => number;
  resultErrPtr: () => number;
  resultErrLen: () => number;
}

const WASM_PATH = resolve(import.meta.dir, '../../src/lib/wasm/jelly.wasm');

let cachedInstance: WasmExports | null = null;
let initPromise: Promise<WasmExports> | null = null;

async function instantiate(): Promise<WasmExports> {
  const wasmBytes = readFileSync(WASM_PATH);
  const mod = await WebAssembly.compile(wasmBytes);

  // Mutable reference so env.getRandomBytes can access memory after instantiation
  let inst!: WebAssembly.Instance;
  const env = {
    getRandomBytes(ptr: number, len: number) {
      const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
      crypto.getRandomValues(new Uint8Array(mem, ptr, len));
    }
  };

  inst = await WebAssembly.instantiate(mod, { env });
  return inst.exports as unknown as WasmExports;
}

/** Get or create the singleton WASM instance. */
export async function getWasm(): Promise<WasmExports> {
  if (cachedInstance) return cachedInstance;
  if (!initPromise) {
    initPromise = instantiate().then((exp) => {
      cachedInstance = exp;
      return exp;
    });
  }
  return initPromise;
}

/** Read a packed (ptr << 32 | len) result from WASM as raw bytes.
 *  Write-ops return CBOR envelope bytes — not JSON. Callers that need
 *  a JSON view run the bytes through parseEnvelopeToJson. */
export function readPackedBytes(exp: WasmExports, packed: bigint): Uint8Array {
  if (packed === 0n) {
    const ep = exp.resultErrPtr();
    const el = exp.resultErrLen();
    const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
    throw new Error(`wasm error: ${msg || '(no diagnostic)'}`);
  }
  const ptr = Number(packed >> 32n);
  const len = Number(packed & 0xffffffffn);
  // Copy — subsequent reset() clobbers linear memory.
  return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

/** Same as readPackedBytes but returns a UTF-8 string. Used by the
 *  parse path which produces JSON text. */
export function readPackedString(exp: WasmExports, packed: bigint): string {
  return new TextDecoder().decode(readPackedBytes(exp, packed));
}

/** Read the 64-byte Ed25519 secret produced by the last mint. */
export function readLastSecret(exp: WasmExports): Uint8Array {
  const len = exp.lastSecretLen();
  if (len !== 64) throw new Error(`lastSecret has wrong length: ${len}`);
  const ptr = exp.lastSecretPtr();
  return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

/** Bitcoin base58 encode — matches the Zig side of the wire. */
const B58_ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
export function base58Encode(bytes: Uint8Array): string {
  if (bytes.length === 0) return '';
  let leadingZeros = 0;
  while (leadingZeros < bytes.length && bytes[leadingZeros] === 0) leadingZeros++;
  const digits: number[] = [];
  for (const b of bytes) {
    let carry = b;
    for (let i = 0; i < digits.length; i++) {
      carry += digits[i] * 256;
      digits[i] = carry % 58;
      carry = Math.floor(carry / 58);
    }
    while (carry) {
      digits.push(carry % 58);
      carry = Math.floor(carry / 58);
    }
  }
  let out = '1'.repeat(leadingZeros);
  for (let i = digits.length - 1; i >= 0; i--) out += B58_ALPHABET[digits[i]];
  return out;
}

export function base58Decode(s: string): Uint8Array {
  if (s.length === 0) return new Uint8Array();
  const pure = s.startsWith('b58:') ? s.slice(4) : s;
  let leadingOnes = 0;
  while (leadingOnes < pure.length && pure[leadingOnes] === '1') leadingOnes++;
  const bytes: number[] = [];
  for (const ch of pure) {
    const idx = B58_ALPHABET.indexOf(ch);
    if (idx < 0) throw new Error(`base58: invalid char '${ch}'`);
    let carry = idx;
    for (let i = 0; i < bytes.length; i++) {
      carry += bytes[i] * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }
    while (carry) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  const out = new Uint8Array(leadingOnes + bytes.length);
  for (let i = 0; i < bytes.length; i++) out[leadingOnes + i] = bytes[bytes.length - 1 - i];
  return out;
}

/** Parse envelope bytes through the WASM parser, returning the DreamBall JSON. */
export function parseEnvelopeToJson(exp: WasmExports, envelopeBytes: Uint8Array): Record<string, unknown> {
  const envPtr = exp.alloc(envelopeBytes.length);
  if (envPtr === 0) throw new Error('parseJelly: alloc failed');
  new Uint8Array(exp.memory.buffer, envPtr, envelopeBytes.length).set(envelopeBytes);
  const packed = exp.parseJelly(envPtr, envelopeBytes.length);
  return JSON.parse(readPackedString(exp, packed)) as Record<string, unknown>;
}

/** Write a string into WASM linear memory and return [ptr, len]. */
export function writeString(exp: WasmExports, s: string): [number, number] {
  const bytes = new TextEncoder().encode(s);
  const ptr = exp.alloc(bytes.length);
  if (ptr === 0) throw new Error('wasm alloc failed');
  new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
  return [ptr, bytes.length];
}

/** Write raw bytes into WASM linear memory and return [ptr, len]. */
export function writeBytes(exp: WasmExports, bytes: Uint8Array): [number, number] {
  const ptr = exp.alloc(bytes.length);
  if (ptr === 0) throw new Error('wasm alloc failed');
  new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
  return [ptr, bytes.length];
}
