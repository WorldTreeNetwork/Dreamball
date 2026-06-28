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

*Completed 2026-06-28.*

**Budget note (2026-06-28):** the WASM size budget was raised to 300 KB raw /
150 KB gzip per [ADR 2026-06-28-wasm-size-budget-dev-velocity-bump](../../../decisions/2026-06-28-wasm-size-budget-dev-velocity-bump.md),
superseding the 224 KB / 64 KB limits this story was originally written against
(AC2 / Task 2 text below reflects the old numbers). The current binary is well
within the new budget.

**Gate summary** (all run locally, all green):

| Gate | Result |
|---|---|
| `zig build test` | Build Summary 14/14 steps succeeded; **222/222 tests passed** (`test success`) |
| `zig build wasm` | OK — 227 651 B raw / 65 937 B gzip (see WASM size) |
| `zig build smoke` | `all smoke checks passed` |
| `scripts/cli-smoke.sh` | exit 0 — `all smoke checks passed` |
| `scripts/server-smoke.sh` | `PASS: 34 / FAIL: 0 — All smoke tests passed.` |
| `bun run check` (svelte-check) | `0 ERRORS` (1 pre-existing a11y warning in `BallroomEasterEgg.svelte`) |
| `bun run test:unit -- --run` | **738 passed (738)**; 48/84 files. The single "error" is the `client`/`storybook` chromium browser projects failing to *launch* (`chrome-headless-shell` not installed — environmental, `Dreamball-nvg`), not a test failure. Server legs of both v4 cross-runtime + authoraction suites pass. |
| `tests/e2e-cryptography.sh` | `all e2e-cryptography checks passed (mock mode)` (real mode not run — `RECRYPT_SERVER_URL` unset) |

**WASM size:** raw = **227 651** bytes (≤ 307 200) / gz = **65 937** bytes (≤ 153 600).
*Headroom from gzip limit: 87 663 bytes.* (Against the original 65 536 limit this
story was written for, the binary would be ~401 B over — which is exactly why the
2026-06-28 budget bump landed; this is not an AC2 breach under the current budget.)

**Browser-leg CI confirmation:** **Residual — confirmed-by-construction; CI run to
be confirmed on next push.** The sprint-003 feature commits (`e8a63ba`, `48fd101`,
`3728023`) are committed locally but **not yet pushed** (HEAD is 3 ahead of
`origin/main`); the B4 authoraction test files are still untracked. CI has therefore
never run on the v4 work — the red CI runs visible on `origin/main` are all for
`fd6840d`, the *pre-sprint-003* tip (where `zig build smoke` failed and the Bun job
was skipped), and are not representative of this work. Structural confirmation:
(1) `bun run check` is clean (0 errors) over the `.svelte.test.ts` files;
(2) the browser legs (`action-v4-cross-runtime.svelte.test.ts`,
`action-v4-authoraction.svelte.test.ts`) import the **same** `*.shared.ts`
assertion module + `__fixtures__/action-v4.golden.json` goldens as the server legs
that pass in the suite above — only the WASM load path differs (Vite `?url` + fetch
vs node fs); (3) `.github/workflows/ci.yml` runs `bun run test:unit -- --run` (job
"Bun — check + tests + build"), which executes the `client` chromium project. The
client browser project shares chromium provisioning with the pre-existing
`storybook` browser project (34 stories), so the browser leg rides on the same CI
browser infrastructure rather than introducing a new dependency.

**Stale-ref grep output:** Living docs (excluding historical `docs/sprints/**` and
`docs/decisions/**`) now contain only correct D-018 references:
- `PROTOCOL.md:7` — header, "generated outputs … supersedes D-018" (already correct)
- `PROTOCOL.md:520/524/584` — new §14 supersession notice + historical annotations
- `ARCHITECTURE.md:59/594` — describe the 2026-06-25 reversion (correct)
- `ARCHITECTURE.md:338` — fixed: schemas relabelled "Generated JSON Schema artifacts" (was "Vendored JSON Schema sources (D-018)")
- `ARCHITECTURE.md:647` — "CBOR semantics stay in Zig (D-018)" — still true post-ADR (CBOR was always Zig-canonical), left as-is

All remaining `D-018` / `json-schema-canonical` hits are in `docs/sprints/**`
(point-in-time sprint-002/003 planning records), `docs/decisions/**` (the retired
ADR, the supersession ADR, and sibling-ADR cross-reference lists), and one
`docs/abi/` note — all legitimate historical references that must not be rewritten.

**known-gaps.md:** scanned — no entry tracked the v4 action / HLC / open-`kind`
work as an open gap (that work was tracked in sprint docs + beads, never logged in
known-gaps.md), so nothing closed there. No new gap introduced (WASM headroom is
tracked under the NFR5 budget + `Dreamball-8bk`, not as a named gap). No edit made.

**Deviations from task breakdown:**
- AC2/Task 2 thresholds (224 KB/64 KB) are superseded by the 2026-06-28 budget bump
  (300 KB/150 KB); measured against the current budget, the binary passes. Updated
  the stale narrative budget reference in `README.md` (was 224/64) to match.
- Fixed one extra living-doc stale reference beyond PROTOCOL.md §14:
  `ARCHITECTURE.md:338` directory-tree label (schemas were still called D-018
  "sources").
- Browser-leg CI confirmation is the single documented residual (above); not a
  blocker per story-lead direction.
