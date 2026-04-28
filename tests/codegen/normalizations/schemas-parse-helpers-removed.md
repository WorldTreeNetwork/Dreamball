# Normalization: schemas-parse-helpers-removed

**ID**: `schemas-parse-helpers-removed`
**Files**: `schemas.ts`
**Kind**: SEMANTIC (intentional sprint-002 hardening)
**Registered**: Story 1.4

## What differs

The legacy generator emits two parse helper functions at the bottom of `schemas.ts`:

```typescript
/** Parse a JSON string to a validated DreamBall. Throws on invalid. */
export function parseDreamBall(jsonText: string): DreamBallValidated { ... }

/** Same as parseDreamBall but returns a tagged result. */
export function safeParseDreamBall(jsonText: string): ParseResult<DreamBallValidated> { ... }
```

The new generator (Story 1.3) does NOT emit these functions. This was an
intentional hardening per NFR8 (validate-on-publish, not validate-on-decode):
the `generated/` directory is the decode-side; validation helpers belong in
`src/lib/parse.ts`, not in the generated module.

## Why it is intentionally different

Per NFR8 and Story 1.3 AC7: the generated `schemas.ts` exports validators
(`DreamBallSchema`, etc.) for use at publish boundaries only. Calling
`parseDreamBall` inside a decode hot-path would violate NFR8. Moving the
helpers out of `generated/` enforces the publish-boundary contract at the
module level.

## Disposition

**Semantic diff — intentional.** Registered here so the diff is explicit and
reviewable rather than silently accepted. Story 1.5 (cutover) removes legacy
entirely; until then, call sites that used `parseDreamBall` from `generated/`
should be migrated to `src/lib/parse.ts`.

Any call site that imports `parseDreamBall` from `src/lib/generated/schemas`
is a bug per Story 1.3 AC7.
