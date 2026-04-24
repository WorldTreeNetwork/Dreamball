# 2026-04-22 — palace mint design decisions

Sprint: sprint-001 · Story: S3.2

## Decision 1: Six-envelope mint pipeline in dependency order

`jelly palace mint` mints exactly six CAS envelopes, in dependency order, so each hash-pointer is resolved before it is referenced:

1. `jelly.dreamball.agent` — oracle agent (own hybrid keypair)
2. `jelly.mythos` — genesis mythos (`is-genesis: true`, no predecessor)
3. `jelly.asset` — archiform registry (`@embedFile`; D-014)
4. `jelly.action` — "palace-minted" dual-signed action (NFR12)
5. `jelly.timeline` — root timeline with `head_hashes = {action.fp}`
6. `jelly.dreamball.field` — palace field (`field-kind: "palace"`)

Each envelope's Blake3 fingerprint feeds into the next. The palace field envelope hashes all five predecessors, so a single `jelly verify` on the bundle validates the entire chain. The six-tuple is also written to the bundle manifest (one hex fp per line, in order: palace, oracle, mythos, registry, action, timeline) so the bridge can reference them by position without reparsing CBOR.

## Decision 2: Zig orchestrates atomicity; bridge only writes DB rows (SEC11)

All six envelopes are written to a staging directory (`<out>.staging.<nanosecond-ts>/`) before the bridge is invoked. The bridge reads the bundle manifest, opens ServerStore, mirrors the palace into LadybugDB (ensurePalace → setMythosHead → Agent node + CONTAINS edge → mirrorAction), and exits 0 on success.

Only if the bridge exits 0 does Zig promote the staging directory to the final CAS and rename the bundle/key files. On any bridge failure, Zig deletes the staging directory and exits non-zero. This means:
- No partial state is visible in the CAS or the DB.
- The bridge cannot corrupt the CAS (it only reads the manifest; it never writes to the filesystem CAS dir).
- The bridge can be replaced or mocked in tests without touching Zig.

SEC11 rationale: the bridge is a subprocess precisely so Zig can gate on its exit code without coupling the two language runtimes at link time.

## Decision 3: Plaintext oracle key with mode 0600 (D-011 / TODO-CRYPTO)

The oracle hybrid keypair is written as a recrypt.identity envelope to `<out>.oracle.key` with POSIX mode 0600. This is intentionally insecure for the MVP — Epic 4 (oracle runtime) will replace it with proper secret custody (HSM, OS keychain, or recrypt encryption).

A `TODO-CRYPTO: oracle key is plaintext` marker is placed adjacent to the write site in `palace_mint.zig` per D-011 and SEC7 tracking.

## Decision 4: @embedFile for seed archiform registry (D-014)

The seed archiform registry (`src/memory-palace/seed/archiform-registry.json`) is embedded at compile time via `@embedFile`. This ensures:
- Two mints from the same binary produce byte-identical registry envelopes (AC5 determinism).
- No runtime filesystem dependency on the registry file location.
- The registry Blake3 is stable across invocations and machines for the same binary version.

When the registry evolves, the binary must be recompiled. This is acceptable for the MVP — registry growth is expected to be infrequent and coordinated.

## Decision 5: Bun subprocess environment patching for std.process.run

`std.Io.Threaded.global_single_threaded` (the Io instance used throughout the CLI) is initialized with `.allocator = .failing` and an empty environment block. When `std.process.run` spawns the bun bridge subprocess, it uses the Threaded instance's internal allocator for the fork/exec arena — causing `OutOfMemory` before the child even starts. Additionally, the empty environment block means the child process receives no environment variables.

The fix applied in `invokeBridge`:
1. Set `std.Io.Threaded.global_single_threaded.allocator = allocator` before spawning (idempotent; single-threaded).
2. Build an `Environ.Map` from `std.c.environ` (the C process environment) and pass it via `RunOptions.environ_map`.

This is not a Zig API bug per se — `init_single_threaded` documents that `.allocator = .failing` is intentional when async/concurrent features are not used, but `processSpawn` unfortunately also uses `t.allocator` for its arena. A future Zig version may address this. Until then, this two-line patch is the minimum required to spawn subprocesses from the single-threaded Io.

## Decision 6: CONTAINS rel table extended to cover Palace→Agent (S3.2)

`schema.cypher`'s `CONTAINS` rel table was originally defined with three pairs: `Palace→Room`, `Room→Inscription`, `Palace→Inscription`. Story 3.2 adds the oracle Agent as a direct child of the Palace, requiring a fourth pair: `Palace→Agent`. This is added to the same multi-pair table to keep containment queries uniform (`MATCH (:Palace)-[:CONTAINS*]->(:Node)`). The bridge creates the Agent node and edge via `store.__rawQuery` since `ServerStore` does not yet expose a dedicated `addAgent` verb (deferred to S3.2 scope boundary).
