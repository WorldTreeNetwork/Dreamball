#!/usr/bin/env bash
# CLI smoke test — exercises every `jelly` command end-to-end.
# Fails fast on any non-zero exit or missing expected output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JELLY="$REPO_DIR/zig-out/bin/jelly"
WORK="$(mktemp -d -t jelly-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if [[ ! -x "$JELLY" ]]; then
  echo "building jelly…"
  (cd "$REPO_DIR" && zig build)
fi

cd "$WORK"

echo "==> version"
"$JELLY" version | grep -q "format-version 1"

echo "==> mint"
"$JELLY" mint --out seed.jelly --name "smoke-test" > mint.out
test -s seed.jelly
test -s seed.jelly.key
grep -q "identity fingerprint" mint.out

echo "==> show (text)"
"$JELLY" show seed.jelly | grep -q "stage:"

echo "==> show (json)"
"$JELLY" show seed.jelly --format=json | grep -q '"type":"jelly.dreamball"'

echo "==> verify (pristine)"
"$JELLY" verify seed.jelly

echo "==> verify (tampered) — must fail"
cp seed.jelly tampered.jelly
python3 -c "
import sys
p='tampered.jelly'
b=bytearray(open(p,'rb').read())
b[60]^=0x01
open(p,'wb').write(bytes(b))
"
if "$JELLY" verify tampered.jelly 2>/dev/null; then
  echo "FAIL: tampered file verified successfully"; exit 1
fi

echo "==> export-json"
"$JELLY" export-json seed.jelly --out seed.jelly.json > /dev/null
grep -q '"type":"jelly.dreamball"' seed.jelly.json

echo "==> seal / unseal (round-trip)"
"$JELLY" seal seed.jelly --out seed.dragon.jelly > /dev/null
"$JELLY" unseal seed.dragon.jelly --out seed.back.jelly > /dev/null
cmp seed.jelly seed.back.jelly

echo "==> grow (bump revision)"
"$JELLY" grow seed.jelly --key seed.jelly.key --set-personality "curious" --revision-bump > grow.out
grep -q "revision=1" grow.out
"$JELLY" verify seed.jelly  # must still verify after re-signing

# --- v2 typed DreamBalls + Demo-D primitives ---
echo "==> mint typed DreamBalls (all six types)"
for t in avatar agent tool relic field guild; do
  "$JELLY" mint --out "$t.jelly" --type "$t" --name "test-$t" > /dev/null
  "$JELLY" show "$t.jelly" | grep -q "type:         $t"
  "$JELLY" verify "$t.jelly"
done

echo "==> join guild"
"$JELLY" join-guild agent.jelly --guild guild.jelly --key agent.jelly.key > join.out
grep -q "joined guild" join.out
"$JELLY" verify agent.jelly

echo "==> transmit tool"
AGENT_FP=$("$JELLY" show agent.jelly | grep fingerprint | awk '{print $2}')
GUILD_FP=$("$JELLY" show guild.jelly | grep fingerprint | awk '{print $2}')
"$JELLY" transmit tool.jelly --to "$AGENT_FP" --via-guild "$GUILD_FP" --sender-key tool.jelly.key --out transmission.jelly > transmit.out
grep -q "transmitted" transmit.out
test -s transmission.jelly

echo "==> seal + unlock relic"
"$JELLY" seal-relic tool.jelly --for-guild "$GUILD_FP" --out sealed.jelly > /dev/null
"$JELLY" unlock sealed.jelly --out unsealed.jelly > /dev/null
cmp tool.jelly unsealed.jelly

echo "==> unknown command — must exit nonzero"
if "$JELLY" not-a-real-command 2>/dev/null; then
  echo "FAIL: unknown command succeeded"; exit 1
fi

echo "all smoke checks passed"
