# Normalization: schemas-parse-result-comment

**ID**: `schemas-parse-result-comment`
**Files**: `schemas.ts`
**Kind**: cosmetic
**Registered**: Story 1.4

## What differs

The new generator emits a JSDoc comment on the `ParseResult` type:

```typescript
/** Tagged-result type used by publish-boundary parse helpers in
 *  `src/lib/parse.ts`. Lives in the generated module so callers
 *  can re-export it without depending on the helpers themselves
 *  (which would re-introduce a validator call site inside
 *  `src/lib/generated/` and break NFR8 / Story 1.3 AC7). */
export type ParseResult<T> = ...
```

The legacy generator emits a section divider comment instead:

```typescript
// ========================================================================
// Convenience — safeParse returning a discriminated result.
// ========================================================================
```

## Why it is semantically equivalent

Both comments document the `ParseResult` type. The new comment is more
precise about the publish-boundary semantics; the legacy comment is a
section divider. Neither changes the emitted TypeScript type definition.

## Disposition

Cosmetic. Strip both comment forms before comparison of the type declaration
itself.
