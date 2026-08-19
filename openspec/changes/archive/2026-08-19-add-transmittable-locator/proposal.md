# add-transmittable-locator

> **ACTIVE BUILD**

## Why

The viewer reads a Transmittable — possible contents of a DreamBall —
fetched by filename and bucket. That is an object-store locator over
existing signed `.ball` bytes, not a new CBOR envelope. Pinning it here
unblocks `add-transmittable-fetch` without touching the wire format or
the fingerprint identity of a DreamBall.

## What

- Capability `transmittable`: app-level locator `{ bucket, filename }`.
- Bytes returned are `application/ball+cbor` (a signed `ball/1`
  envelope). `dreamball.wasm` `verifyBall` / `parseBall` is the only
  decode path.
- Not a wire type. No `ball.transmittable` envelope, no schema-gen, no
  golden vector, no PROTOCOL.md field.
- Fingerprint remains the DreamBall's identity on the wire. Bucket +
  filename are store keys only.
- Secret keys never come back with the bytes.
- Missing object is a typed not-found, not an empty ball.
- Human-facing encoding of the same locator is query params
  `bucket` + `filename` (consumed later by `add-dreamball-viewer-app`).

## Impact

- Capabilities: ADDED `transmittable`
- ADRs: none

## User journey & surfaces

No new UI because this change only names the locator. An observer will
open the later viewer with `?bucket=&filename=`; empty is "no locator",
failed is typed not-found or wasm verify/parse error, off is the
existing fingerprint `GET /dreamballs/:fp` path which this does not
remove. Fetch implementation is `add-transmittable-fetch`.

## Out of scope

- HTTP/S3/R2 client and dreamball-server route (`add-transmittable-fetch`, `Dreamball-5hs.4`)
- Viewer route `/view` (`add-dreamball-viewer-app`, `Dreamball-5hs.5`)
- Shell lens (`add-dreamball-shell-lens`)
- New protocol type / Rust-canonical envelope (rejected path B)
- Replacing fingerprint identity or `HttpBackend.load(fp)`
