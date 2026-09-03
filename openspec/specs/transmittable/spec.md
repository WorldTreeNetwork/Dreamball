# transmittable

Living capability. Folded from `add-transmittable-locator` on 2026-08-19.

A Transmittable is an object-store locator for signed DreamBall bytes.
It is not a wire type.

## Requirements

### Requirement: Transmittable is a store locator, not a wire type

A Transmittable SHALL be the pair `{ bucket: string, filename: string }`.
It SHALL address bytes in an object store. It SHALL NOT be a CBOR
envelope, a `DreamBallType` variant, or a generated protocol struct.

#### Scenario: Locator fields

- GIVEN a Transmittable
- WHEN a consumer reads it
- THEN it has a non-empty `bucket` and a non-empty `filename`, and no
  other field is required to fetch

#### Scenario: Not on the wire

- GIVEN `docs/PROTOCOL.md` and `src/protocol.zig`
- WHEN this change is folded
- THEN neither file gains a `ball.transmittable` type, and
  `bun run codegen` is not required for the locator

### Requirement: Locator bytes are a signed DreamBall envelope

The bytes fetched for a Transmittable SHALL be `application/ball+cbor`
(a signed `ball/1` envelope). The only decode path SHALL be
`dreamball.wasm` `verifyBall` then `parseBall`. TypeScript SHALL NOT
hand-decode CBOR.

#### Scenario: Happy path

- GIVEN a locator whose object is a valid signed `.ball`
- WHEN the bytes are verified and parsed
- THEN the result is a typed `DreamBall` whose identity is still its
  fingerprint, not the bucket or filename

#### Scenario: Missing object

- GIVEN a locator whose object does not exist
- WHEN fetch is attempted
- THEN the caller receives a typed not-found and no DreamBall is
  invented

#### Scenario: Corrupt or unsigned-against-policy bytes

- GIVEN a locator whose object exists but `verifyBall` or `parseBall`
  fails
- WHEN the viewer handles the result
- THEN the failure is the wasm reason/code, not a second parser's
  message

### Requirement: Fingerprint identity is unchanged

Bucket and filename SHALL be store keys only. A DreamBall's identity
SHALL remain its Ed25519 fingerprint. Existing
`GET /dreamballs/:fp` SHALL keep working.

#### Scenario: Two address spaces

- GIVEN the same DreamBall stored under a locator and under its
  fingerprint
- WHEN one consumer loads by `bucket`+`filename` and another by
  fingerprint
- THEN both decode to the same identity bytes after wasm parse

### Requirement: Secrets stay out of the locator path

A Transmittable fetch SHALL NOT return `secret_key_b58`, key files, or
other secret material. The response SHALL be envelope bytes only.

#### Scenario: Key file is not the object

- GIVEN a store that also holds `.key` files
- WHEN a locator fetch succeeds
- THEN the body is `.ball` bytes and no key material is included
