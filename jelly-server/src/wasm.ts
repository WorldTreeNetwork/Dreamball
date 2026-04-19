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
  mintDreamBall: (typeId: number, namePtr: number, nameLen: number, nowSecs: bigint) => bigint;
  growDreamBall: (ptr: number, len: number) => bigint;
  joinGuildWasm: (ptr: number, len: number) => bigint;
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

/** Read a packed (ptr << 32 | len) result from WASM, return as UTF-8 string. */
export function readPackedString(exp: WasmExports, packed: bigint): string {
  if (packed === 0n) {
    const ep = exp.resultErrPtr();
    const el = exp.resultErrLen();
    const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
    throw new Error(`wasm error: ${msg || '(no diagnostic)'}`);
  }
  const ptr = Number(packed >> 32n);
  const len = Number(packed & 0xffffffffn);
  return new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ptr, len));
}

/** Write a string into WASM linear memory and return [ptr, len]. */
export function writeString(exp: WasmExports, s: string): [number, number] {
  const bytes = new TextEncoder().encode(s);
  const ptr = exp.alloc(bytes.length);
  if (ptr === 0) throw new Error('wasm alloc failed');
  new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
  return [ptr, bytes.length];
}
