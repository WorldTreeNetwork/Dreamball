#!/usr/bin/env bash
#
# deploy-renderer.sh — build the vendored DreamBall Web renderer and ship it to
# a static /vendor/ with content-hashed, cache-correct filenames.
#
#   scripts/deploy-renderer.sh [ssh-host] [remote-vendor-dir]
#     defaults: xibu  /root/dashboard_v3/public/vendor
#
# Flow:
#   1. build  → release/dreamball-web-renderer/dreamball-renderer-<hash>.js + manifest.json
#   2. read the hashed name from the manifest
#   3. stamp it into the page template (deploy/xibudojo/star-tamagotchi.html → __RENDERER__)
#   4. scp the hashed bundle + page to the host's /vendor/
#
# Why hashed names: the host serves .js with `Cache-Control: immutable`, which is
# only correct when the URL changes on content change. The page is served
# no-cache, so it always points at the current hashed bundle — no hard-refresh,
# no ?v= cache-busting.
set -euo pipefail

HOST="${1:-xibu}"
REMOTE_DIR="${2:-/root/dashboard_v3/public/vendor}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/release/dreamball-web-renderer"
TEMPLATE="$ROOT/deploy/xibudojo/star-tamagotchi.html"

echo "▸ building renderer…"
( cd "$ROOT" && bun run build:renderer >/dev/null )

BUNDLE="$(node -e "process.stdout.write(require('$OUT/manifest.json')['dreamball-renderer.js'])")"
[ -n "$BUNDLE" ] || { echo "✗ no bundle in manifest"; exit 1; }
echo "▸ bundle: $BUNDLE"

STAGED="$(mktemp -d)/star-tamagotchi.html"
sed "s#__RENDERER__#$BUNDLE#" "$TEMPLATE" > "$STAGED"

echo "▸ uploading to $HOST:$REMOTE_DIR …"
scp "$OUT/$BUNDLE" "$HOST:$REMOTE_DIR/$BUNDLE"
scp "$STAGED" "$HOST:$REMOTE_DIR/star-tamagotchi.html"

echo "✓ deployed. page → /vendor/star-tamagotchi.html  bundle → /vendor/$BUNDLE"
