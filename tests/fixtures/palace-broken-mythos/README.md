# palace-broken-mythos fixture

Synthetic palace bundle used by S3.4 AC4 smoke and S3.6 AC8 invariant (d).

## Structure

```
palace.bundle        — fake palace bundle (synthetic fps for palace/oracle/registry/action/timeline)
palace.cas/          — CAS directory containing only the broken mythos envelope
  9ff586e8...507    — the broken mythos CBOR envelope (Blake3 fp)
broken-mythos.cbor  — the raw CBOR bytes of the broken mythos
```

## What makes it broken

The single mythos envelope in `palace.cas/` is a valid dCBOR `jelly.mythos` with:
- `is-genesis: false`
- `predecessor: deadbeefdeadbeef...deadbeef` (32 bytes — a sentinel value NOT present in the CAS)

When `walkToGenesis` (from `mythos-chain.zig`) tries to resolve the predecessor fp from
the CAS, it finds nothing and returns `unresolvable_predecessor`. This is the AC4 / S3.6
invariant (d) "unresolvable predecessor" violation.

## Usage

```bash
# AC4 smoke: jelly verify should exit non-zero naming the break
jelly verify tests/fixtures/palace-broken-mythos/palace.bundle
# Expected: exit non-zero; stderr mentions broken fp

# S3.6 invariant (d) test:
# palace_verify.zig imports mythos-chain.zig and calls walkToGenesis on this fixture.
```

## Regeneration

If the dCBOR encoding changes, regenerate with:

```bash
python3 - <<'EOF'
# (see scripts that produced broken-mythos.cbor — uses hand-rolled dCBOR)
# Predecessor bytes: 0xDEADBEEF * 8 (32 bytes total)
# Compute new Blake3 fp: zig run /tmp/gen_fixture4.zig
# Update palace.bundle line 3 and rename palace.cas/<old_fp> to palace.cas/<new_fp>
EOF
```
