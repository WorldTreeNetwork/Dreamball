# Normalization: cbor-test-new-only

**ID**: `cbor-test-new-only`
**Files**: `cbor.test.ts`
**Kind**: structural (new file, no legacy equivalent)
**Registered**: Story 1.4

## What differs

The new generator (Story 1.3) emits `src/lib/generated/cbor.test.ts` — a Vitest
test file that round-trips the CBOR decoder against the envelope golden fixtures
in `fixtures/envelope_golden/`.

The legacy generator does not emit a test file. Test co-generation was introduced
as part of the JSON-Schema-canonical pipeline (D-018) to ensure the decoder is
always tested against the authoritative golden bytes.

## Why it is intentionally absent from legacy

The legacy generator pre-dates test co-generation. Adding `cbor.test.ts` to the
legacy generator would require it to understand the golden fixture paths, which
are a Story 1.3+ concept.

## Disposition

**Structural diff — new file only.** `cbor.test.ts` is excluded from the
file-set comparison (registered in `NEW_ONLY_FILES`). Its presence in the new
generator is not a regression; its absence from legacy is expected.

Story 1.5 (cutover) removes the legacy directory; at that point `cbor.test.ts`
is the only test file and the normalization is no longer needed.
