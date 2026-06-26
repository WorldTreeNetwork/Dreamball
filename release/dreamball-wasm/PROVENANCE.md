# dreamball.wasm — provenance

- **Protocol epoch:** ball/1 (package 0.1.0)
- **Source commit:** `a4fd58cde1404f0470857af955457f9530ea405c`
- **Build:** `zig build wasm` (ML-DSA-87 verify linked; `-Dpq-wasm=true` default)
- **SHA-256:** `2f06bd3d264234c2eee5cca20f00cb8eadc47ba24c012c52e6814afc0861db15`
- **Size:** 215794 bytes raw, 62608 bytes gzipped (budget: ≤ 224 KB raw / ≤ 64 KB gzipped)

Vendor this directory into the consumer (e.g. the web/ client repo). The
binary's only host requirement is one import: `env.getRandomBytes(ptr, len)`
backed by a CSPRNG. Types in `dreamball.d.ts`. Verify integrity with
`shasum -a 256 -c dreamball.wasm.sha256`.

Regenerate with `scripts/build-vendor-wasm.sh`.
