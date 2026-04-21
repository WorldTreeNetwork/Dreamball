# 2026-04-21 — Adopt recrypt.identity envelope for per-DreamBall key material

## Status

Accepted. Closes the "durable key-storage story" from `docs/known-gaps.md §6`.

## Context

Dreamball's per-DreamBall signing keys are currently stored in a hand-rolled hybrid format (`DJELLY\n` magic + version byte + ed25519 secret + ML-DSA-87 public + ML-DSA-87 secret) implemented in `src/key_file.zig`. This bespoke schema is tight and efficient, but:

1. It encodes only Dreamball's signing flows; identity material is a cross-tool concern.
2. The recrypt project (sibling to Dreamball) has already shipped a durable, tested identity envelope type (`recrypt.identity`) with canonical fixtures and a determinism spec.
3. Adopting a shared envelope type unblocks cross-tool identity exchange and positions Dreamball for optional future wallet-container consumption without committing to it now.

The recrypt identity envelope (specified in `recrypt/docs/wallet-envelope-format.md` §3.2 and `recrypt/docs/dcbor-determinism.md`) carries the same signing-key material Dreamball needs, preserves unknown assertions for forward compatibility, and guarantees byte-for-byte interop via canonical fixtures.

## Decision

We adopt `recrypt.identity` Gordian Envelope as the sole format for Dreamball's per-DreamBall key material. We replace the ad-hoc `DJELLY\n` layout with raw envelope bytes on disk, while maintaining backward compatibility with legacy ed25519-only 64-byte files. The interop contract is recrypt's determinism spec + canonical fixtures; we vendor those fixtures and enforce byte-identical round-trip in our tests.

## Drivers

- **Shared fingerprint algorithm.** Both recrypt and Dreamball use Blake3(ed25519_public) to anchor identity material. Using the same envelope type means fingerprints computed across tools are guaranteed identical — no divergence, no custom translation layer.

- **Canonical fixtures as the interop contract.** Recrypt ships three fixture envelopes (ed25519-only, hybrid-no-pre, full-with-pre) alongside their parsed representations. These are the authoritative byte-level contract. Zig and Rust readers that pass fixture tests on both sides are proven interoperable without separate negotiation.

- **Vocabulary parity with recrypt wire protocol.** Recrypt's documentation (`wire-protocol.md`, `dcbor-determinism.md`, `identity-self-signature.md`) uses established terminology (subject, assertions, predicates, tags 200/201, dCBOR rules). By adopting the same envelope type, Dreamball inherits that vocabulary; readers and maintainers can consult a single reference instead of cross-checking bespoke Dreamball docs.

- **Forward compatibility via unknown-assertion preservation.** The envelope format allows new assertions (e.g., Dreamball-specific metadata like `"dreamball-lineage"`) to be embedded and round-tripped without schema changes. This leaves room for identity extensions without versioning friction.

## Alternatives considered

**1. Keep the `DJELLY\n` hybrid format.**
Rejected. Hand-rolled schemas age poorly. The hybrid layout is Dreamball-only; there is no path to sharing it with recrypt tooling or future wallet-container support without a rewrite anyway. Staying with it trades technical debt for a marginal space savings (the envelope wrapper is ~50 bytes overhead per identity).

**2. Invent a Dreamball-specific envelope type (e.g., `dreamball.identity`).**
Rejected. Pointless divergence. If we need an envelope at all, we should use the shared type and reduce the surface area for cryptographic mistakes. Custom envelope types are a signal that we did not coordinate with upstream projects on a shared schema.

**3. Wait for recrypt v2 wallet container (`recrypt.wallet`) before adopting any envelope.**
Rejected. The wallet container is a larger piece of work (multi-identity storage, encrypted shell, self-signatures). Dreamball has no multi-identity concept and no encrypted-at-rest requirement for MVP. Blocking on the wallet container defers the identity-envelope benefit (interop + shared vocabulary) while Zig-side key-material handling remains bespoke. The identity envelope stands alone and unblocks us immediately.

## Why chosen

This is the smallest surface that unblocks cross-tool identity exchange and positions us for optional future wallet-container consumption without committing to a larger feature we don't need today. The recrypt envelope type is already shipped, tested, and documented; adopting it costs us a CBOR reader extension + fixture tests, not a new spec or negotiation with another team.

## Consequences

- **Interop contract is recrypt's `dcbor-determinism.md` + canonical fixtures.** We vendor the three fixture envelopes from `recrypt/tests/fixtures/identity/` and commit them under `vendor/recrypt-identity-fixtures/`. A `VENDOR.md` in that directory records the source recrypt commit, regeneration tool, and refresh procedure. When recrypt updates its fixtures, we pin the commit, re-copy, and re-run our fixture tests. If bytes diverge, either recrypt's format evolved (we update our codec + docs) or one side has a bug.

- **Fixture refresh is a manual procedure.** The fixtures are point-in-time snapshots. We do not auto-regenerate them from recrypt's test harness. Instead, we maintain a named refresh procedure (`cargo test -p recrypt-wire --test fixture_regenerate -- --ignored` on the recrypt side, then copy to Dreamball). This keeps the commitment explicit and the fixture lifecycle traceable in Git.

- **Zig-side self-signature emission is deferred.** The envelope format supports `'signed'` assertions (CBOR tag 40020 + KnownValue(3)). Emitting those requires additional encoding machinery and only makes sense when a consumer needs them (e.g., wallet-container adoption or cross-tool signature verification). For MVP, we parse and preserve unsigned envelopes fine; signing is left as a follow-up.

- **Key file swap is transparent to callers.** `src/key_file.zig` remains the public interface; the envelope codec is an internal detail. Callers read envelopes without knowing they are envelopes. Legacy ed25519-only 64-byte files continue to parse. The `DJELLY\n` format is rejected with a clear error directing users to regenerate.

- **No deployed artefacts to migrate.** Per project policy (`docs/known-gaps.md §6), no migration of existing `.key` files. The CLI rejects `DJELLY\n` files and instructs the user to run `jelly mint` to generate a fresh key.

## Follow-ups

1. **Zig self-signature emission (Vision tier).** When a consumer (wallet container, cross-tool verification) emerges, implement the `'signed'` assertion encoding in `src/identity_envelope.zig`. Requires `tag 40020` wrapper + canonical CBOR for the signature payload.

2. **Wallet container consumption (Vision tier).** Recrypt's `recrypt.wallet` envelope type carries multi-identity storage and encrypted-at-rest semantics. IF Dreamball ever needs multi-identity support (e.g., multi-user agents, delegated keyspaces), adopt `recrypt.wallet` as a container and nest the `recrypt.identity` envelopes inside it. No decision needed today; deferred pending a use case.

3. **Recrypt recipient envelope (conditional).** Recrypt may ship a `recrypt.recipient` envelope type for PRE-only parties (identity material without signing keys). Dreamball's current signing flow is identity-hybrid; recryption hops live in recrypt-server. If a use case emerges for Dreamball to author identity for agents that participate in recryption without signing authority, adopt `recrypt.recipient` then. No requirement yet.

## References

- `docs/known-gaps.md §6` — the gap this ADR closes
- `.omc/plans/2026-04-21-dreamball-identity-envelope.md` — detailed implementation plan
- `../recrypt/docs/wallet-envelope-format.md §3.2` — identity envelope structure
- `../recrypt/docs/dcbor-determinism.md` — interop contract for deterministic serialization
- `../recrypt/docs/identity-self-signature.md` — deferred feature (self-sig emission)
- `../recrypt/crates/recrypt-wire/src/identity.rs` — reference implementation
- `../recrypt/tests/fixtures/identity/README.md` — fixture semantics and canonical test cases
