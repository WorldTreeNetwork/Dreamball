# WASM authoring ABI — `dreamball.wasm` 0.1.0 (`ball/1`)

> Audience: consumers calling the authoring exports from JS (browser + Bun).
> Source of truth: [`src/wasm_main.zig`](../../src/wasm_main.zig) — every claim
> below is quoted from it. Reference loader: [`src/lib/wasm/loader.ts`](../../src/lib/wasm/loader.ts).
> Reference test (a passing worked example): [`src/lib/wasm/sign-action-envelope.test.ts`](../../src/lib/wasm/sign-action-envelope.test.ts).
> Written 2026-06-24 in answer to World-Tree `web/`'s ABI request.

## TL;DR — the one correction that unblocks you

**`signActionEnvelope` is misnamed for what it does. It is a raw Ed25519
signing primitive over arbitrary bytes — it does NOT build an envelope.**

It does not know what a `ball.action` is. It does not set `parent_hashes`,
`content_hash`, `timestamp`, or an HLC. It takes `(64-byte secret, payload
bytes)` and returns `64 signature bytes`. **You** build the action structure,
canonicalise it, hash it, and decide what bytes to sign. There is no native
action-envelope authoring export in 0.1.0 (the `ball.action` encoder exists in
Zig — `src/protocol_v2.zig`, `src/envelope_v2.zig` — but is **not** wired to a
WASM export yet; see asks 6–8).

That single fact answers most of section 1 of your request. The verified
worked example is at the bottom.

## Memory & result protocol

| Export | Purpose |
|---|---|
| `memory` | exported `WebAssembly.Memory` (linear memory) |
| `alloc(size: u32) -> u32` | bump-allocate `size` bytes; returns ptr, **0 on OOM** |
| `reset() -> void` | rewind the bump allocator + clear last-error. **Frees every prior `alloc`** — re-copy inputs after a reset |
| `resultErrPtr() -> u32` / `resultErrLen() -> u32` | UTF-8 diagnostic string for the last failed call |

**The packed-result convention is NOT uniform.** It applies only to the exports
that return `u64`. Verify/hash exports use different encodings:

| Export | Return encoding |
|---|---|
| `parseBall`, `mintDreamBall`, `growDreamBall`, `joinGuildWasm`, `signActionEnvelope` | packed `u64 = (ptr << 32) \| len`; **`0` = error** → read `resultErr*` |
| `verifyBall` | `i32`: `2` all sigs verified · `1` parsed, no Ed25519 sig · `0` verify failed · `-1` parse error |
| `verifyMlDsa` | `i32`: `1` verified · `0` failed · `-1` parse/setup error (also `-1` if built without `-Dpq-wasm`) |
| `hashBlake3` | `void` — writes 32 bytes to a caller-provided `out_ptr`; **no error path** |
| `mintDreamBall` secret side-channel | secret key lands in a static buffer; read via `lastSecretPtr()` / `lastSecretLen()` |

JS unpack of a packed `u64` (note: it arrives as a JS `BigInt`):
```js
const ptr = Number(packed >> 32n);
const len = Number(packed & 0xffffffffn);
const out = new Uint8Array(exp.memory.buffer, ptr, len).slice(); // copy out before next reset()
```

### Host import (the one integration seam)
```
extern "env" fn getRandomBytes(ptr: u32, len: u32) void;   // wasm_main.zig:43
```
You must supply it at instantiation. It fills `ptr[0..len]` with CSPRNG bytes.
Used by `mintDreamBall` (keygen seed) only. **`signActionEnvelope` does not use
it** — Ed25519 signing is deterministic.
```js
const env = { getRandomBytes(ptr, len) {
  crypto.getRandomValues(new Uint8Array(inst.exports.memory.buffer, ptr, len));
}};
```

## Per-export ABI

### 1. `signActionEnvelope` — the critical one  (`wasm_main.zig:583`)
```
signActionEnvelope(keypair_ptr: u32, keypair_len: u32,   // 64-byte Ed25519 secret
                   payload_ptr: u32, payload_len: u32)    // arbitrary bytes
  -> u64 packed (sig_ptr << 32 | sig_len)                // sig_len is always 64
```
- **Inputs:** `(secret bytes, secret len=64)` + `(payload bytes, payload len)`.
  The payload is **whatever bytes you choose to sign** — typically your
  canonical dCBOR action payload. Not a pre-built envelope; not parsed.
- **Key:** a pointer to **key bytes you hold in JS memory**. No internal
  keystore. Must be exactly **64 bytes** = Zig Ed25519 secret = `[seed(32) ||
  pubkey(32)]` (same bytes `mintDreamBall` writes to `lastSecret`). `len != 64`
  → error.
- **Algorithm:** **Ed25519 only.** No ML-DSA, no hybrid (deferred — D-023 / SEC6,
  see comment at `wasm_main.zig:575`). PQ signing stays CLI-side.
- **Output:** the **64 raw signature bytes**. It does **not** set
  `parent_hashes` / `content_hash` / `timestamp` / HLC — you do, before signing.
- **Error:** returns `0`; diagnostic in `resultErr*`.

### 2. `mintDreamBall`  (`wasm_main.zig:205`)
```
mintDreamBall(type_id: u32, name_ptr: u32, name_len: u32, created: i64)
  -> u64 packed (env_ptr << 32 | env_len)    // signed envelope bytes
```
- `type_id`: `0`=avatar `1`=agent `2`=tool `3`=relic `4`=field `5`=guild
  `6`=untyped(v1). `>6` → error.
- `name_len == 0` ⇒ unnamed. `created` = Unix **seconds** (`i64`).
- **Generates an Ed25519 keypair internally** via `getRandomBytes`. It does
  **not** take a key. The 64-byte secret lands in the static `lastSecret`
  buffer — **read it immediately** via `lastSecretPtr()`/`lastSecretLen()`
  (len `64`) before any subsequent `mintDreamBall` overwrites it.
- Output = the signed `.ball` envelope (**Ed25519-only** — browser/Bun mint
  never attaches PQ; legal under PROTOCOL.md §2.3). Public key (32 B) is the
  envelope's `identity` field, and equals `secret[32..64]`.

### 3. `hashBlake3`  (`wasm_main.zig:738`)
```
hashBlake3(input_ptr: u32, input_len: u32, out_ptr: u32) -> void
```
- `out_ptr` **must** point at a pre-`alloc`'d region of **≥ 32 bytes**
  (`exp.alloc(32)`). Writes the **raw 32-byte** Blake3-256 digest. No return,
  no error path. (`loader.ts` `blake3Hex` wraps this to hex.)

### 4. `verifyMlDsa`  (`wasm_main.zig:536`)
```
verifyMlDsa(sig_ptr, sig_len, msg_ptr, msg_len, pk_ptr, pk_len: u32) -> i32
```
- `sig_len` **must** be `4627` (ML-DSA-87 / FIPS-204 Cat-5); `pk_len` **must**
  be `2592`. Returns `1` verified · `0` failed · `-1` length/setup error or
  build lacks `-Dpq-wasm`. (Default build ships PQ verify.)

### 5. `growDreamBall`  (`wasm_main.zig:370`)
```
growDreamBall(env_ptr, env_len,
              secret_ptr, secret_len,        // 64-byte Ed25519 secret
              new_name_ptr, new_name_len,    // new_name_len==0 ⇒ keep name
              updated: i64,
              promote_to_dreamball: u32)      // !=0 promotes stage seed→dreamball
  -> u64 packed (env_ptr << 32 | env_len)     // bumped revision, re-signed (Ed25519)
```
- `secret_len != 64` → error. Decodes the envelope, bumps `revision`, sets
  `updated`, optional rename + promote, **re-signs Ed25519-only**.

### bonus: `joinGuildWasm`  (`wasm_main.zig:288`)
```
joinGuildWasm(env_ptr,env_len, guild_env_ptr,guild_env_len,
              secret_ptr,secret_len /*=64*/, updated: i64)
  -> u64 packed envelope     // appends guild fingerprint, bumps revision, re-signs
```

### Verify/parse (already wrapped in `loader.ts`)
- `parseBall(ptr,len) -> u64 packed JSON`; `verifyBall(ptr,len) -> i32` (2/1/0/-1).

## Key management (answers to your identity questions)

- **Generation:** `mintDreamBall` mints an **Ed25519** keypair from
  host randomness. **No `jelly.key-bundle` / hybrid keypair is produced by the
  WASM in 0.1.0.** The identity *is* the Ed25519 keypair; its public half is the
  envelope's `identity` field.
- **Serialization / lengths:** secret = **64 B** `[seed(32)||pubkey(32)]`;
  public = **32 B**; Ed25519 signature = **64 B**. (PQ constants exist —
  `ML_DSA_87` pubkey `2592`, secret `4896`, sig `4627`, `src/protocol.zig:74-80`
  — but PQ keys are CLI-minted, not WASM-minted.)
- **Where the private key lives when signing:** **in your JS memory; you pass a
  pointer.** The WASM keeps no keystore. So your registry = "pubkey (32 B,
  hex/base58) per user", and you store/unlock the 64-B secret yourself.
- **Hybrid/PQ identity** (one user → Ed25519 + ML-DSA-87) requires the native
  CLI (`dreamball grow --key <hybrid-key-file>`); the browser cannot mint or
  sign PQ in 0.1.0.

## Answers to asks 6–10

6. **Nested-slot decoder — not yet.** `parseBall` typed-decodes core, signatures,
   `look/feel/act` (+ nested `asset`/`skill`) and `archiform-fp`; the slots
   `memory / knowledge-graph / emotional-register / interaction-set /
   guild-policy` are **skipped, not surfaced** (`loader.ts:11-24`, tracked as
   Dreamball-m97). There is **no** lower-level "decode this CBOR slot" export
   today. The fix is schema-driven (extend `schemas/root-2.0.0.json` +
   regenerate `cbor.ts`), not a hand-written decoder — when it lands and the
   wasm rebuilds, the browser upgrades for free. **For your own op payloads,
   don't wait on this:** carry them as bytes you encode/decode yourself and sign
   via `signActionEnvelope` (see worked example).

7. **HLC `[l,c]` — not native.** Neither the v1 envelope nor the v2 `ball.action`
   struct (`src/protocol_v2.zig:327`, fields: `action_kind, parent_hashes,
   actor, target_fp, timestamp, deps, nacks`) carries a logical clock. **Carry
   HLC inside your op payload for now** (it's covered by your `content_hash`
   because you hash the payload yourself). Native is the right long-term home
   but it's a protocol change — file it against the `ball.action` manifest work
   (`docs/decisions/2026-04-25-action-manifest.md`).

8. **Custom schemas — the archiform registry is the intended path, but it's
   sprint-002.** New typed field sets are meant to be defined as *archiform*
   schemas vendored from aspects.sh, not hand-written
   (`docs/decisions/2026-04-25-archiform-registry.md`,
   `…-json-schema-canonical.md`). That registration/codegen path is **not landed
   in 0.1.0.** Until it is, use a **generic typed-map payload that you encode and
   validate yourself** (Valibot on your side), and sign the canonical bytes.
   Your `crdt-op / object3d / kanban-card` types live in your code for now;
   migrate them to archiform schemas when the registry ships.

9. **dCBOR parity — yes, by construction.** Canonical determinism (map-key
   ordering "shorter-then-lexicographic", verbatim item preservation) is
   enforced in `src/dcbor.zig`, and the browser and Bun load the **same**
   `dreamball.wasm` bytes. The only host seam is `getRandomBytes`, which never
   touches encoding. So `content_hash` over identical logical input is
   byte-identical across browser, Bun, and the native CLI (the CLI shares the
   same Zig code path — `parseBall` is "guaranteed byte-identical", `loader.ts:6`).
   Golden vectors live in `src/golden.zig`. **Caveat:** this guarantee covers
   bytes the *Zig* code encodes. For *your* op payloads you must apply the same
   dCBOR discipline yourself (or, better, route them through a future encode
   export) — `signActionEnvelope` signs exactly the bytes you give it, so op
   identity is only stable if your encoder is deterministic.

10. **Versioning.** Package is `dreamball` (npm `version` currently `0.0.1`);
    schemas are versioned files (`schemas/root-2.0.0.json`,
    `memory-palace-0.1.0.json`); the wire ball format is `ball/1`. Releases are
    tag-driven (`.github/workflows/release.yml`) and ship CLI binaries + the wasm
    bundle + npm. **Until the npm package is the distribution channel, pin by
    vendoring `dreamball.wasm` + a recorded version; we'll bump those together
    and note ABI changes here.** The `.wasm` bytes are the interface.

## Worked example (verified end-to-end against vendored 0.1.0 wasm)

Mint a keypair → author a payload → sign → verify. This ran green against
`src/lib/wasm/dreamball.wasm` (output: `verify good payload: true`,
`verify tampered payload: false`). Adapt into your `web/src/lib/dreamball.ts`
exactly like the `parseBall` pattern. Note `loader.ts` already exports a thin
`signActionEnvelope(keypairBytes, payload)` wrapper — but it does **not** wrap
`mintDreamBall`/`lastSecret*`, so the raw-instance form below is what you need
for the full mint→sign→verify loop.

```js
import { readFileSync } from 'node:fs';

const mod = await WebAssembly.compile(readFileSync('dreamball.wasm'));
let inst;
inst = await WebAssembly.instantiate(mod, { env: {
  getRandomBytes: (p, n) => crypto.getRandomValues(new Uint8Array(inst.exports.memory.buffer, p, n)),
}});
const w = inst.exports;

const enc = new TextEncoder();
const copy = (u8) => { const p = w.alloc(u8.length); new Uint8Array(w.memory.buffer, p, u8.length).set(u8); return p; };
const readPacked = (packed) => {
  if (packed === 0n) throw new Error('wasm err: ' +
    new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.resultErrPtr(), w.resultErrLen())));
  return new Uint8Array(w.memory.buffer, Number(packed >> 32n), Number(packed & 0xffffffffn)).slice();
};
const toAB = (u8) => { const b = new ArrayBuffer(u8.byteLength); new Uint8Array(b).set(u8); return b; };

// 1. mint identity → 64-byte secret [seed(32)||pub(32)]; read secret BEFORE next mint
w.reset();
readPacked(w.mintDreamBall(0 /*avatar*/, copy(enc.encode('kanban-user')), 11, BigInt(Math.floor(Date.now()/1000))));
const secret64 = new Uint8Array(w.memory.buffer, w.lastSecretPtr(), w.lastSecretLen()).slice(); // 64
const pubRaw   = secret64.slice(32, 64); // raw Ed25519 public key (32)

// 2. author YOUR action payload — HLC, parent_hashes, content_hash are your job.
//    (Use a deterministic dCBOR encoder in real code; JSON here for illustration.)
const payload = enc.encode(JSON.stringify({
  kind: 'crdt-op', op: 'card.move', card: 'c-42', col: 'done',
  hlc: [Date.now(), 0], parent_hashes: [],
}));

// content_hash via the wasm's Blake3 (same digest in every runtime)
const outPtr = w.alloc(32), inPtr = copy(payload);
w.hashBlake3(inPtr, payload.length, outPtr);
const contentHash = new Uint8Array(w.memory.buffer, outPtr, 32).slice(); // 32-byte op id

// 3. sign the canonical payload bytes (Ed25519, deterministic)
w.reset();                                   // frees prior allocs — re-copy
const sig = readPacked(w.signActionEnvelope(copy(secret64), 64, copy(payload), payload.length)); // 64 bytes

// 4. verify (Web Crypto; pubkey = secret[32..64])
const pk = await crypto.subtle.importKey('raw', toAB(pubRaw), { name: 'Ed25519' }, false, ['verify']);
const ok = await crypto.subtle.verify({ name: 'Ed25519' }, pk, toAB(sig), toAB(payload)); // true
```

### Gotchas that will bite you
- **`reset()` frees everything** from the bump allocator. Re-`copy` inputs after
  each reset (the example resets between mint and sign and re-copies).
- **Copy packed results out immediately** (`.slice()`) — the next `reset()`/op
  can clobber that memory.
- **Read `lastSecret` right after `mintDreamBall`** — a later mint overwrites it.
- **Pointers are byte offsets into `exp.memory.buffer`** — and that buffer object
  can change if memory grows; always re-read `w.memory.buffer` after a call that
  may `alloc`, rather than caching the view.
- Packed returns are **`BigInt`** in JS (`0n`, `>> 32n`).
