# 2026-06-28 — WASM size budget: dev-velocity bump (224→300 KB raw, 64→150 KB gzip)

**Status:** accepted (temporary; restoration tracked)
**Supersedes the numeric ceiling in:** ADR 2026-06-25-zig-canonical-supersedes-json-schema
(which set raw ≤ 224 KB / gzip ≤ 64 KB). The *reasoning* of that ADR — gzip is the
binding over-the-wire constraint, raw is secondary — still holds; only the numbers move.

## Context

Sprint-003 (open type system) adds `verifyAction` to the WASM surface
(story B2, bead `Dreamball-14d`): the browser-side verification path for v4
`ball.action` envelopes. `verifyAction` recovers the signer by calling
`envelope_v2.decodeAction` on the stripped, canonical unsigned bytes — the same
two-call (`stripSignatures` → `decodeAction`) pattern `verifyBall` uses.

`verifyAction` is the **first WASM caller of `decodeAction`**. Until now the
binary linked only the *encoders* (`authorAction`, `encodeActionV4`) plus
`verifyBall`'s `decodeDreamBallSubject` path. Linking `decodeAction` pulls in the
entire v3/v4 decode path — `assertCanonical`, the core-map walk, ActionRef /
deps / nacks / target-fp / timestamp handling, and the v3 closed-enum arm —
about **+2 KB gzip**. Measured:

| build            | raw     | gzip    |
|------------------|---------|---------|
| pre-B2 (e8a63ba) | 220 751 | 63 557  |
| with verifyAction| 226 757 | 65 614  |

65 614 exceeds the old 65 536 (64 KB) gzip ceiling by **78 bytes**. B1's close
note already flagged that the gzip headroom was razor-thin (~1.8 KB) after
linking `envelope_v2`; B2 is the path that consumed the rest.

## Decision

Raise the size gate to **≤ 300 KB raw (307 200) / ≤ 150 KB gzip (153 600)** as a
deliberate, temporary **dev-velocity budget with generous headroom**. The product
owner chose to bump the ceiling now — keep landing the v4 surface fast, with no
size-anxiety for the rest of the open-type-system work — rather than block the
B-epic on a size-optimization pass. This is a conscious override of the
"gzip is hard, never bump it" default in the 2026-06-25 ADR.

Margin rationale: the binary is ~65.6 KB gzip / 226.8 KB raw today. 150 KB gzip /
300 KB raw is intentionally far above that — enough room to add every remaining
decode path the open type system needs (each ~2 KB gzip) without touching this
gate again. It is a *fast-iteration ceiling*, not an estimate of where the binary
will land; the binary should stay far below it.

## The bill comes due — restoration is tracked, not forgotten

The gzip budget exists because it is the **over-the-wire cost** every browser
consumer pays. The 150 KB ceiling is deliberately generous so size never blocks
iteration during the open-type-system work — but the *actual* binary must not be
allowed to drift up to fill it. This bump is explicitly temporary:

- **`Dreamball-8bk`** owns restoring a **tight gzip budget** (target back toward
  ~64 KB) via the optimization pass: candidates are an `rdynamic` symbol strip,
  dropping the unused float formatter, dead-code elimination, and/or a lighter
  action-core-only actor reader for `verifyAction` that shares already-resident
  dCBOR primitives instead of linking all of `decodeAction`. That bead also
  re-tightens this CI/release gate once the binary is back down.
- 150 KB is a fast-iteration ceiling, not a target. Watch the *measured* gzip
  size (printed in CI) — if it climbs toward 100 KB without a deliberate reason,
  that is the signal to do the optimization pass, not to relax further.

## Where the numbers live (kept in lockstep)

- `.github/workflows/ci.yml` — PR size gate
- `.github/workflows/release.yml` — release size gate
- `scripts/build-vendor-wasm.sh` — PROVENANCE.md budget string
- `CLAUDE.md` — Build section budget note
- `build.zig` — stale narrative comment (references the older 200 KB figure; not a gate)
