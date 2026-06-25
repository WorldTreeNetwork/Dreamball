# Releasing dreamball

Releases are **tag-driven**. The git tag is the single source of truth for
the version number; CI refuses to publish anything whose tag does not match
`package.json`. The workflow lives in
[`.github/workflows/release.yml`](../../.github/workflows/release.yml).

## What a release ships

A pushed `vX.Y.Z` tag produces a GitHub Release with:

| Asset | Source | Notes |
|-------|--------|-------|
| `dreamball-vX.Y.Z-x86_64-linux-musl.tar.gz`  | `zig build cli` | static (musl) |
| `dreamball-vX.Y.Z-aarch64-linux-musl.tar.gz` | `zig build cli` | static (musl) |
| `dreamball-vX.Y.Z-aarch64-macos.tar.gz`      | `zig build cli` | native mac runner |
| `dreamball-vX.Y.Z-x86_64-macos.tar.gz`       | `zig build cli` | native mac runner |
| `dreamball-vX.Y.Z.wasm` (+ `.sha256`, `.d.ts`, `.PROVENANCE.md`) | vendored `release/dreamball-wasm/` | size-gated, lockstep-verified |
| `SHA256SUMS` | aggregated | covers every asset above |

Each CLI tarball contains the `dreamball` binary, the `ball` alias
(relative symlink), and `README.md`. Release notes are auto-generated from
the commits between the previous tag and this one.

Separately, the Svelte library is published to npm as `dreamball@X.Y.Z`
(with [provenance](https://docs.npmjs.com/generating-provenance-statements)),
**only if** an `NPM_TOKEN` repo secret is configured. Without it the npm job
logs a warning and is skipped — the GitHub Release still ships.

## Versioning rule

The tag must be semver `vMAJOR.MINOR.PATCH` (a `-prerelease` suffix is
allowed) and must equal `package.json`'s `version`. The `guard` job hard-fails
otherwise, so the binary, the wasm bundle, and the npm package always carry
the same number. Keep `build.zig.zon`'s `version` in sync too — it is not
machine-enforced yet, but it should not drift.

## Cutting a release

```bash
# 1. Bump the version in package.json (and build.zig.zon) and commit it.
#    e.g. 0.1.0 -> 0.1.1
git commit -am "release: 0.1.1"

# 2. Make sure CI is green on main, then tag and push.
git tag -a v0.1.1 -m "dreamball 0.1.1"
git push origin main
git push origin v0.1.1
```

Pushing the tag triggers `Release`. Watch it under the repo's **Actions**
tab; the GitHub Release appears under **Releases** when the `release` job
finishes.

## Dry run (no Release, no publish)

Use the **Run workflow** button (`workflow_dispatch`) on the Release
workflow and pass an existing tag (e.g. `v0.1.1`) as the `ref` input. This
runs the `guard`, `cli`, and `wasm` jobs and uploads the built assets as
**workflow artifacts**, but the `release` and `npm` jobs are skipped because
they are gated on `is_tag == true` (real tag pushes only). Good for
validating a build before committing to a real tag.

## One-time setup

- **npm publishing** — confirm the unscoped name `dreamball` is owned by your
  org on npmjs (otherwise the first publish 403s), then create an npm
  automation token and add it as the `NPM_TOKEN` repository secret
  (Settings → Secrets and variables → Actions). The package is published with
  `--access public`.
- **GitHub Release permissions** — handled in-workflow via
  `permissions: contents: write`; no manual setup needed.

## Why tag-driven

A single immutable tag fixes the version across three independently
distributed artifacts (CLI binaries, the wasm bundle, the npm package). If
the version lived in a file edited at release time, those three could drift.
Deriving it from the tag — and failing the build on any mismatch — makes a
mis-numbered release structurally impossible rather than merely discouraged.
