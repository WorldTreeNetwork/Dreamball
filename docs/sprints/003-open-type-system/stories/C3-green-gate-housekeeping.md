---
id: C3
epic: C
title: Green-gate + housekeeping (all gates, wasm budget, stale D-018 ref)
status: ready
test_tier: thorough
decisions: [zig-canonical-2026-06-25]
frs: [FR11]
nfrs: [NFR1, NFR5]
closes_beads: [Dreamball-2f3]
---

# C3 — Green-gate + housekeeping

## Context

C3 is the final story of sprint-003. It runs after all prior stories (A1–A5,
B1–B4, C1, C2) have merged. No new protocol surface is added here; the job is
integration hygiene and documentation consistency.

Three concrete risks must be resolved before this story can close:

**1. WASM gzip headroom is razor-thin.** The baseline entering the sprint was
220 751 bytes raw / 63 761 bytes gzip. The CI hard limits are 229 376 bytes
(224 KB) raw and 65 536 bytes (64 KB) gzip — a gzip margin of just ~1 775
bytes. Sprint-003's WASM work (B1 linked `envelope_v2` into the WASM module)
may have consumed some or all of that headroom. If any earlier story pushed the
binary over budget, the resolution is Dreamball-8bk (size reduction work), not
relaxing the limit.

**2. The browser-leg cross-runtime test was committed but never run locally.**
C1 committed `action-v4-cross-runtime.svelte.test.ts` (the jsdom/browser-mode
Vitest project) with disk 100% full on the development machine (Dreamball-nvg),
blocking local execution. CI is the first environment where it will actually run.
C3 must confirm the test is green in CI; a failure is a C1 regression, not a
new C3 defect.

**3. PROTOCOL.md §14 still describes JSON Schema as a canonical vendored
artifact.** The 2026-06-25 Zig-canonical ADR reclassified `schemas/*.json` from
canonical sources (the D-018 contract) to generated outputs of `zig build
schemagen`. The PROTOCOL.md header was updated at the time, but §14 still
describes a workflow where schemas are "vendored locally," "fetched" from
aspects.sh, and pinned as inputs — the D-018-era contract. This must be
corrected. The epics document names it "Requirements Conflict #1."

## Acceptance Criteria

1. **All integration gates pass.** Every gate below runs to completion with zero
   failures, both locally and confirmed in CI (`.github/workflows/ci.yml`):

   | Gate | Command |
   |---|---|
   | Zig unit tests | `zig build test` |
   | CLI end-to-end (Zig) | `zig build smoke` |
   | CLI end-to-end (shell) | `scripts/cli-smoke.sh` |
   | Server end-to-end | `scripts/server-smoke.sh` |
   | TypeScript type-check | `bun run check` |
   | Vitest (all projects, incl. browser leg) | `bun run test:unit -- --run` |
   | Crypto pipeline | `tests/e2e-cryptography.sh` |

   `zig build test` must report ≥ 51 passing. `bun run check` must report 0
   errors. `tests/e2e-cryptography.sh` runs in mock mode by default; if
   `RECRYPT_SERVER_URL` is set, it must also pass in real mode.

2. **WASM size gate is green post-merge.** `zig build wasm` produces a binary
   ≤ 229 376 bytes (224 KB) raw and ≤ 65 536 bytes (64 KB) gzip. Measure both
   values and record them in the Dev Agent Record. If either limit is breached,
   stop and resolve via Dreamball-8bk before closing this story. The gzip limit
   is the binding constraint; do not propose a raw-budget relaxation as a
   workaround for gzip overage.

3. **Browser-leg cross-runtime test confirmed green in CI.** The file
   `action-v4-cross-runtime.svelte.test.ts` (client/jsdom Vitest project,
   committed in C1) must appear in the passing output of the `bun run test:unit
   -- --run` CI step. Evidence: CI run URL recorded in the Dev Agent Record.
   Investigate any failure against C1's three pinned golden constants
   (`GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX`, `GOLDEN_ACTION_V4_CONTENT_HASH`,
   `GOLDEN_ACTION_V4_SIGNED_BYTES_HEX`) and the jsdom WASM loader path.

4. **Stale JSON-Schema-canonical framing removed from `docs/PROTOCOL.md §14`.**
   The section is updated to reflect that `schemas/*.json` are generated outputs
   of `zig build schemagen` (per the 2026-06-25 ADR), not canonical vendored
   sources. Specifically:

   - A supersession notice is added at the top of §14 pointing to the
     2026-06-25 ADR.
   - The §14.4 update lifecycle is marked as pre-ADR / historical.
   - The `schemas:refresh` entry in §14.3 is annotated as the pre-ADR
     maintenance path (no longer the primary update workflow).
   - The correct update path — "edit Zig types → `zig build schemagen` →
     commit generated outputs" — is stated.
   - Historical content is retained (it documents the byte-equivalence
     fixture baseline), but no surviving prose treats schemas as
     authoritative inputs.

5. **No other stale D-018 / JSON-Schema-canonical references survive.** A grep
   over `docs/` for `D-018` and variants of `json-schema-canonical` finds hits
   only inside the retired ADR file (`2026-04-25-json-schema-canonical.md`) and
   the superseded-by banners in the 2026-06-25 ADR. Any other hit is fixed or
   annotated before this story closes.

6. **`docs/known-gaps.md` reflects sprint-003 completions.** Scan for open
   gaps that sprint-003 resolved. For each that closed, add a dated `✅ Closed
   <date>` line. If no gap closed, document that no changes were needed (so
   the scan is on record).

7. **`README.md` Roadmap updated.** Sprint-003 deliverables are reflected in
   the Roadmap section. Any roadmap bullet resolved by the open type system
   work is ticked or removed.

## Task Breakdown

### 1. Confirm all gates green (run locally first)

Run the gates in this order — each is a prerequisite to the next:

```
zig build test
zig build wasm                  # triggers size measurement in step 2
zig build smoke
scripts/cli-smoke.sh
bun run check
bun run test:unit -- --run      # includes browser-mode leg; see step 3
scripts/server-smoke.sh
tests/e2e-cryptography.sh
```

If a gate fails, triage against the story that owns the affected surface (A1–C2).
Fix the defect in the relevant file scope; do not paper over it here.

### 2. WASM size measurement and record

Immediately after `zig build wasm` succeeds:

```sh
raw=$(wc -c < src/lib/wasm/dreamball.wasm)
gz=$(gzip -9c src/lib/wasm/dreamball.wasm | wc -c)
echo "dreamball.wasm: ${raw} bytes raw / ${gz} bytes gzip"
test "$raw" -le 229376 || { echo "RAW BUDGET EXCEEDED"; exit 1; }
test "$gz"  -le 65536  || { echo "GZIP BUDGET EXCEEDED — resolve via Dreamball-8bk"; exit 1; }
```

Record the exact raw and gz byte counts in the Dev Agent Record. If the gzip
limit is breached, do not close this story and do not bump the budget — work
Dreamball-8bk first.

### 3. Confirm browser-leg test appears in CI

Pull the CI log for the `bun — check + tests + build` job on the commit that
first includes C1's `action-v4-cross-runtime.svelte.test.ts`. Confirm the test
file appears in the Vitest summary with a PASS verdict. Record the CI run URL
in the Dev Agent Record.

If the test is missing from the output (project not picked up by Vitest config):
inspect `vitest.config.ts` / `vitest.workspace.ts` to confirm the `client`
project includes `*.svelte.test.ts` files and that the jsdom environment is
declared.

If the test fails: compare actual output against the three C1 golden constants.
The most likely failure mode is a golden mismatch, meaning C1's KAT was written
against a different WASM binary than what CI rebuilt.

### 4. Fix PROTOCOL.md §14 — retire the D-018 canonical-source framing

Open `docs/PROTOCOL.md`. Locate §14 ("Schema vendoring and pin format"). Add
the following supersession notice immediately after the section heading and
`*Implements D-029…*` line:

```markdown
> **Status change (2026-06-25 — supersedes D-018):** Per the
> [Zig-canonical ADR](decisions/2026-06-25-zig-canonical-supersedes-json-schema.md),
> `schemas/*.json` are **generated artifacts** — outputs of `zig build schemagen` —
> not canonical vendored sources. The §14.4 update lifecycle and the
> `schemas:refresh` tool below describe the pre-ADR (D-018) workflow and are
> retained for historical context only. The correct update path is: edit
> `src/protocol*.zig` → run `zig build schemagen` → commit the regenerated
> outputs together with the updated pin files.
```

In §14.3, prefix the `schemas:refresh` table row description with
"(Pre-ADR / historical)".

In §14.4 heading or preamble, add "(Pre-ADR / historical)" to make it clear
this lifecycle is no longer operative.

Do not delete the historical content — the byte-equivalence gate still depends
on the vendored fixtures as comparison targets until Dreamball-m97.2 (the real
comptime generator) produces them.

### 5. Grep for other stale D-018 references

```sh
grep -rn "D-018\|json-schema-canonical\|JSON-Schema-canonical" docs/ --include="*.md"
```

Expected hits (acceptable):
- `docs/decisions/2026-04-25-json-schema-canonical.md` — the retired ADR itself
- `docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md` — the
  supersession record (mentions D-018 throughout as the thing being superseded)
- `docs/PROTOCOL.md` header — already correctly says "supersedes D-018"
- §14 after the fix in step 4

Any other hit is a stale reference. Fix inline or add an annotated
cross-reference to the 2026-06-25 ADR.

### 6. Update known-gaps.md and README.md

**`docs/known-gaps.md`:** Review the "Active gaps" list. Sprint-003 candidates:
- The HLC spec and v4 action wire type are now specified and implemented; if any
  gap entry was tracking them as open, close it.
- No new gaps were introduced by sprint-003 (the WASM size headroom is tracked
  in the existing NFR5 budget, not as a named gap).

**`README.md`:** Locate the Roadmap section. Update sprint-003 deliverables
(v4 action envelope, open `kind` system, cross-runtime golden gate, HLC wire
spec). Tick or remove completed bullets.

## Test Plan

- Gate run: all 7 gates from AC1 produce zero failures. Paste final output
  summary into Dev Agent Record.
- Size assertion: `raw ≤ 229376` and `gz ≤ 65536` verified by the shell
  commands in step 2; exact counts recorded.
- Browser-leg CI confirmation: CI run URL in Dev Agent Record; test name appears
  as PASS in the Vitest summary.
- Stale-ref grep: grep output shows no unexpected hits beyond the known
  acceptable set (retired ADR + supersession ADR + PROTOCOL.md header).
- PROTOCOL.md diff: supersession notice present in §14 preamble; §14.4 and
  §14.3 `schemas:refresh` marked historical; no surviving prose treats schemas
  as authoritative inputs.

## Files

- `docs/PROTOCOL.md` — §14 update (supersession notice, historical annotations)
- `docs/known-gaps.md` — close any sprint-003 items resolved
- `README.md` — roadmap update
- This story file (Dev Agent Record section, completed post-implementation)

No source files under `src/` are expected to change in C3. If a gate failure
requires a source fix, make it in the relevant A/B/C story's scope and record
the fix here with a pointer.

## Dependencies

All sprint-003 stories must be merged before C3 executes: A1, A2, A3, A4, A5,
B1, B2, B3, B4, C1, C2. C3 is the integration seam — its gates will fail if
any prior story left a broken invariant. Running C3 gates before all prior
stories land is a signal that a dependency is missing, not that C3 is the
source of the failure.

---

## Dev Agent Record

*(Complete this section post-implementation.)*

**Gate summary:** *(paste terminal output or CI job links)*

**WASM size:** raw = ??? bytes / gz = ??? bytes
*(Headroom from gzip limit: ??? bytes)*

**Browser-leg CI confirmation:** *(CI run URL; confirm
`action-v4-cross-runtime.svelte.test.ts` listed as PASS)*

**Stale-ref grep output:** *(paste grep result; confirm no unexpected hits)*

**Deviations from task breakdown:** *(list any, or "none")*
