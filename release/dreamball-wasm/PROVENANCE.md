# dreamball.wasm — provenance

- **Protocol epoch:** ball/1 (package 0.1.0)
- **Source commit:** `eda924fdc6493b53c3c61384b73dbab83d1b3048`
- **Build:** `zig build wasm` (ML-DSA-87 verify linked; `-Dpq-wasm=true` default)
- **SHA-256:** `3cd6b40a57c726d4535b5eb974644980f72cb944f546e891b6f69857c9b42529`
- **Size:** 227651 bytes raw, 65937 bytes gzipped (budget: ≤ 300 KB raw / ≤ 150 KB gzipped; dev-velocity bump 2026-06-28, tightening tracked in Dreamball-8bk)

Vendor this directory into the consumer (e.g. the web/ client repo). The
binary's only host requirement is one import: `env.getRandomBytes(ptr, len)`
backed by a CSPRNG. Types in `dreamball.d.ts`. Verify integrity with
`shasum -a 256 -c dreamball.wasm.sha256`.

Regenerate with `scripts/build-vendor-wasm.sh`.
