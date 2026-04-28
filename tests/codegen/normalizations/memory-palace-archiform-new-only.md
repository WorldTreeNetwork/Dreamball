# Normalization: memory-palace-archiform-new-only

**ID**: `memory-palace-archiform-new-only`
**Files**: `memory-palace.schemas.ts`, `memory-palace.types.ts`
**Kind**: structural (new files, no legacy equivalent)
**Registered**: Story 1.4 (discovered during integration with parallel Story 2.2)

## What differs

The new generator (Story 2.2) emits per-archiform TypeScript files:
- `src/lib/generated/memory-palace.schemas.ts` — Valibot validators for Memory Palace types
- `src/lib/generated/memory-palace.types.ts` — TypeScript interfaces for Memory Palace types

The legacy generator does not emit any archiform-specific files. The legacy generator
predates the archiform registry design (D-017) and has no concept of per-archiform
code generation.

## Why it is intentionally absent from legacy

The archiform system was designed in sprint-002 (D-017, D-018). The legacy generator
(`tools/schema-gen/legacy/main.zig`) was written for the root DreamBall protocol only,
before the JSON-Schema-canonical pipeline and the archiform extension mechanism existed.
There is no expectation that the legacy generator emit archiform-specific files.

## Disposition

**Structural diff — new files only.** These files are excluded from the file-set
comparison (registered in `NEW_ONLY_FILES`). Their presence in the new generator is
correct per D-018 (JSON Schema as canonical source) and D-017 (archiform registry).

Story 1.5 (cutover) removes the legacy directory entirely; at that point these are
the canonical archiform output files with no normalization needed.
