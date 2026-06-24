# dreamball.wasm — provenance

- **Protocol epoch:** ball/1 (package 0.1.0)
- **Source commit:** `75c836d6eb069ce871dc0a38d273db8e01988f4d`
- **Build:** `zig build wasm` (ML-DSA-87 verify linked; `-Dpq-wasm=true` default)
- **SHA-256:** `fe1f73179d5234f6a771c7f7a74bd4540b9c2d72f4c10ec09bdbb7021672158f`
- **Size:** 177989 bytes raw, 51495 bytes gzipped (budget: ≤ 200 KB raw / ≤ 64 KB gzipped)

Vendor this directory into the consumer (e.g. the web/ client repo). The
binary's only host requirement is one import: `env.getRandomBytes(ptr, len)`
backed by a CSPRNG. Types in `dreamball.d.ts`. Verify integrity with
`shasum -a 256 -c dreamball.wasm.sha256`.

Regenerate with `scripts/build-vendor-wasm.sh`.
