# Star animation stage

> **ACTIVE BUILD** — browser first, idle float and click reaction explicitly selected by the user.

Star needs an inexpensive animated browser stage. The demo loads the existing signed capsule and GLB, then presents a float loop and a touch-triggered bounce/spin with pause and seek controls. A renderer-independent local document defines curves; a scoped player handles touch and reaction lifecycle events; a small Three.js adapter draws the pose.

Capability: `character-animation`. Tracking: `Dreamball-juv`.

No protocol changes: `ball.timeline` remains causal history, and `Stage` remains the capsule lifecycle enum. Animation documents are currently authored locally, not embedded in the signed capsule. Script execution, a WASM animation host, channel-name transmission and full pi-calculus semantics are follow-up architecture work.

The UI shows loading and failure states, rejects unverified capsules, provides keyboard-accessible controls, and respects reduced motion. Rendering uses a 30 fps ceiling, bounded resolution, visibility suspension, studio lighting and a painted contact shadow.
