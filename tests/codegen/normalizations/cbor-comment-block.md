# Normalization: cbor-comment-block

**ID**: `cbor-comment-block`
**Files**: `cbor.ts`
**Kind**: cosmetic
**Registered**: Story 1.4

## What differs

`cbor.ts` opens with a multi-line comment describing the decoder. The new
generator rewrote this comment to reflect the D-018 direction (JSON-Schema
canonical, encode side in Zig/WASM, decode side is this file only):

New generator comment includes:
```
// Per D-018 the ENCODE side is the canonical Zig algorithm exposed
// to the browser via the `encode_cbor` WASM primitive (Story 1.5);
// this file ships the read-side decoder for incoming `.jelly`
// bytes only.
//
// Per NFR8 / Story 1.3 AC7: this decoder does NOT call Valibot.
// Validation runs at publish boundaries via `src/lib/parse.ts`.
```

Legacy generator comment includes:
```
// For v2 MVP we only need decode (incoming .jelly files from the
// jelly-server). Encode path stays on the Zig side.
```

## Why it is semantically equivalent

Both describe the same dCBOR decoder with the same functional content. The
new comment adds D-018/NFR8 framing that is directional guidance, not a
behavioral change to the decoder implementation.

## Disposition

Cosmetic. Strip the opening comment block from both before byte-comparison.
The functional decoder code (classes, functions, exports) is verified to
be byte-equivalent below the comment block.
