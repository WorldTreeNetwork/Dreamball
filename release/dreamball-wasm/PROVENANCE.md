# dreamball.wasm — provenance

- **Protocol epoch:** ball/1 (package 0.1.0)
- **Source commit:** `8859d32054871ead264ede8ad7dfcdcfd7449241`
- **Build:** `zig build wasm` (ML-DSA-87 verify linked; `-Dpq-wasm=true` default)
- **SHA-256:** `f13e0c88e02950cd8ed1326ee49f4dff7cf0907bb06513b5a620457a89fa12c5`
- **Size:** 177989 bytes raw, 51492 bytes gzipped (budget: ≤ 200 KB raw / ≤ 64 KB gzipped)

Vendor this directory into the consumer (e.g. the web/ client repo). The
binary's only host requirement is one import: `env.getRandomBytes(ptr, len)`
backed by a CSPRNG. Types in `dreamball.d.ts`. Verify integrity with
`shasum -a 256 -c dreamball.wasm.sha256`.

Regenerate with `scripts/build-vendor-wasm.sh`.
