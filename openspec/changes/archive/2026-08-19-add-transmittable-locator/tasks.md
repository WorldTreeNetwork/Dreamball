# Tasks

- [x] Add a TypeScript locator type `{ bucket: string; filename: string }`
      in the Svelte lib (hand-written adapter type — not generated from
      Zig/Rust; this is not a wire type)
- [x] Document the locator in `docs/` (short note under ARCHITECTURE or
      a viewer paragraph): store keys vs fingerprint identity; bytes are
      signed `.ball`; wasm is the decoder
- [x] Name the not-found and verify/parse failure cases so fetch can
      implement them without inventing a second error vocabulary
- [x] Update `Dreamball-5hs.1` when the contract is in source + docs

Findings (not boxes): path A was the intend default; Duke activated this
node without picking a wire type. Fetch stays a later change.
