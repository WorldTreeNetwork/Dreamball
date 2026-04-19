#!/usr/bin/env bash
# End-to-end cryptography pipeline test.
#
# Skip-gated on RECRYPT_SERVER_URL — when set, exercises the real two-hop
# signing flow (WASM Ed25519 + recrypt-server ML-DSA-87). When unset,
# runs in mock-crypto mode and documents what the real path would check.
#
# Status (2026-04-19): recrypt-server does not yet expose POST /sign/ml-dsa.
# The endpoint is Phase D work tracked in docs/known-gaps.md. This test
# is the destination contract — it should be the FIRST thing that goes
# green when the recrypt-server change lands.
#
# Usage:
#   RECRYPT_SERVER_URL=http://127.0.0.1:9810 ./tests/e2e-cryptography.sh
#   # or without — runs the mocked-crypto variant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JELLY="$REPO_DIR/zig-out/bin/jelly"
WORK="$(mktemp -d -t jelly-e2e-crypto.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"

echo "==> Pre-flight: jelly CLI built?"
if [[ ! -x "$JELLY" ]]; then
  (cd "$REPO_DIR" && zig build)
fi

MODE="mock"
if [[ -n "${RECRYPT_SERVER_URL:-}" ]]; then
  MODE="real"
  echo "==> RECRYPT_SERVER_URL=$RECRYPT_SERVER_URL — real-crypto mode"
  # Confirm recrypt-server is actually reachable.
  if ! curl -sSf "${RECRYPT_SERVER_URL}/health" > /dev/null; then
    echo "FAIL: recrypt-server unreachable at $RECRYPT_SERVER_URL"
    exit 1
  fi
else
  echo "==> RECRYPT_SERVER_URL unset — mock-crypto mode (ML-DSA placeholder)"
fi

echo "==> 1. Mint a real Ed25519-signed Agent DreamBall"
if [[ "$MODE" == "real" ]]; then
  "$JELLY" mint --out alice.jelly --type agent --name "alice" --ml-dsa-server "$RECRYPT_SERVER_URL"
else
  "$JELLY" mint --out alice.jelly --type agent --name "alice"
fi
test -s alice.jelly
test -s alice.jelly.key

echo "==> 2. Verify Ed25519 signature passes"
"$JELLY" verify alice.jelly
# TODO-CRYPTO: in real mode, verify both signatures pass strict policy.
# Blocked on recrypt-server adding POST /sign/ml-dsa — tracked in
# docs/known-gaps.md.

echo "==> 3. Mint a Guild"
"$JELLY" mint --out guild.jelly --type guild --name "the-hummingbirds"

echo "==> 4. Join Alice to the Guild"
"$JELLY" join-guild alice.jelly --guild guild.jelly --key alice.jelly.key > /dev/null
"$JELLY" verify alice.jelly  # re-verify after re-sign

echo "==> 5. Mint a Tool"
"$JELLY" mint --out tool.jelly --type tool --name "haiku-compose"

echo "==> 6. Transmit Tool to Alice via the Guild"
ALICE_FP=$("$JELLY" show alice.jelly | grep fingerprint | awk '{print $2}')
GUILD_FP=$("$JELLY" show guild.jelly | grep fingerprint | awk '{print $2}')
"$JELLY" transmit tool.jelly \
  --to "$ALICE_FP" \
  --via-guild "$GUILD_FP" \
  --sender-key tool.jelly.key \
  --out transmission.jelly > /dev/null
test -s transmission.jelly
# TODO-CRYPTO: in real mode, the tool-envelope field should be recrypt-
# wrapped, not plaintext. Blocked on Phase D recrypt integration.

echo "==> 7. Seal a Relic under the Guild"
"$JELLY" seal-relic tool.jelly --for-guild "$GUILD_FP" --out sealed.jelly > /dev/null
test -s sealed.jelly
# TODO-CRYPTO: in real mode, the sealed payload is proxy-recrypted under
# the Guild keyspace. Blocked on Phase D.

echo "==> 8. Unlock the Relic"
"$JELLY" unlock sealed.jelly --out unlocked.jelly > /dev/null
cmp tool.jelly unlocked.jelly
# TODO-CRYPTO: real unlock requires Guild member key. Blocked on Phase D.

if [[ "$MODE" == "real" ]]; then
  echo ""
  echo "==> REAL CRYPTO MODE — additional checks"
  echo "    Once Phase D lands, this section should:"
  echo "    - Verify isFullySigned(.strict) on every envelope"
  echo "    - Confirm sealed.jelly's payload is real ciphertext (not plaintext)"
  echo "    - Prove only Guild members can unlock"
  echo "    - Confirm transmission.jelly's tool-envelope is recrypt-wrapped"
  echo ""
  echo "    These checks are currently documented but not asserted — they"
  echo "    flip on when recrypt-server exposes POST /sign/ml-dsa + the"
  echo "    recryption endpoints for keyspace-scoped wrapping."
fi

echo ""
echo "all e2e-cryptography checks passed ($MODE mode)"
