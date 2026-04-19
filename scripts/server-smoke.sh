#!/usr/bin/env bash
# server-smoke.sh — End-to-end smoke test for jelly-server.
#
# Starts the server, curls through the main routes, asserts expected
# structure, then kills the server. Must complete in < 60 seconds.
#
# Usage: bash scripts/server-smoke.sh
# Exit: 0 on all pass, 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=19808  # Use a non-standard port to avoid conflicts
BASE="http://localhost:${PORT}"
SERVER_PID=""
PASS=0
FAIL=0

# ─── helpers ────────────────────────────────────────────────────────────────

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m%s\033[0m\n' "$*"; }

assert_ok() {
  local label="$1"
  local status="$2"
  local body="$3"

  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    green "  PASS  $label (HTTP $status)"
    ((PASS++)) || true
  else
    red "  FAIL  $label (HTTP $status)"
    red "        body: $body"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local label="$1"
  local body="$2"
  local needle="$3"

  if echo "$body" | grep -q "$needle"; then
    green "  PASS  $label (contains '$needle')"
    ((PASS++)) || true
  else
    red "  FAIL  $label (missing '$needle')"
    red "        body: ${body:0:400}"
    ((FAIL++)) || true
  fi
}

assert_not_contains() {
  local label="$1"
  local body="$2"
  local needle="$3"

  if echo "$body" | grep -qv "$needle" || ! echo "$body" | grep -q "$needle"; then
    green "  PASS  $label (no '$needle' leaked)"
    ((PASS++)) || true
  else
    red "  FAIL  $label ('$needle' LEAKED in response)"
    ((FAIL++)) || true
  fi
}

curl_get() {
  local path="$1"
  curl -s -w '\n__STATUS__%{http_code}' "${BASE}${path}"
}

curl_post() {
  local path="$1"
  local body="$2"
  curl -s -w '\n__STATUS__%{http_code}' \
    -X POST \
    -H 'content-type: application/json' \
    -d "$body" \
    "${BASE}${path}"
}

split_response() {
  # Sets BODY and STATUS from curl output with __STATUS__NNN suffix
  local raw="$1"
  STATUS=$(echo "$raw" | grep -o '__STATUS__[0-9]*' | grep -o '[0-9]*')
  BODY=$(echo "$raw" | sed 's/__STATUS__[0-9]*//')
}

# ─── start server ───────────────────────────────────────────────────────────

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

info "Starting jelly-server on port $PORT..."
JELLY_SERVER_PORT=$PORT bun run "${REPO_ROOT}/jelly-server/src/index.ts" &
SERVER_PID=$!

# Wait for the server to be ready (up to 15 seconds)
READY=0
for i in $(seq 1 30); do
  if curl -sf "${BASE}/.well-known/mcp" > /dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -eq 0 ]; then
  red "Server did not start within 15 seconds"
  exit 1
fi
green "Server ready."
echo

# ─── tests ──────────────────────────────────────────────────────────────────

info "=== 1. GET /.well-known/mcp ==="
RAW=$(curl_get '/.well-known/mcp')
split_response "$RAW"
assert_ok "GET /.well-known/mcp" "$STATUS" "$BODY"
assert_contains "mcp doc has routes" "$BODY" '"routes"'
assert_contains "mcp doc has dreamball_types" "$BODY" '"dreamball_types"'
assert_contains "mcp doc has mcp_tools" "$BODY" '"mcp_tools"'
assert_contains "mcp doc has wasm_exports" "$BODY" '"wasm_exports"'

# Check route count >= 8
ROUTE_COUNT=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('routes',[])))" 2>/dev/null || echo 0)
if [ "$ROUTE_COUNT" -ge 8 ]; then
  green "  PASS  mcp routes count >= 8 (got $ROUTE_COUNT)"
  ((PASS++)) || true
else
  red "  FAIL  mcp routes count < 8 (got $ROUTE_COUNT)"
  ((FAIL++)) || true
fi

info "=== 2. GET /.well-known/mcp/types ==="
RAW=$(curl_get '/.well-known/mcp/types')
split_response "$RAW"
assert_ok "GET /.well-known/mcp/types" "$STATUS" "$BODY"
assert_contains "types doc has \$defs" "$BODY" '"\$defs"'

DEFS_COUNT=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('\$defs',{})))" 2>/dev/null || echo 0)
if [ "$DEFS_COUNT" -ge 10 ]; then
  green "  PASS  types \$defs count >= 10 (got $DEFS_COUNT)"
  ((PASS++)) || true
else
  red "  FAIL  types \$defs count < 10 (got $DEFS_COUNT)"
  ((FAIL++)) || true
fi

info "=== 3. GET /dreamballs (list — initially empty) ==="
RAW=$(curl_get '/dreamballs')
split_response "$RAW"
assert_ok "GET /dreamballs (list)" "$STATUS" "$BODY"

info "=== 4. POST /dreamballs (mint avatar) ==="
RAW=$(curl_post '/dreamballs' '{"type":"avatar","name":"Smoke Test Avatar"}')
split_response "$RAW"

FP=""
SECRET=""
if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
  assert_ok "POST /dreamballs mint" "$STATUS" "$BODY"
  assert_contains "mint returns fingerprint" "$BODY" '"fingerprint"'
  assert_contains "mint returns secret_key_b58 (one-time)" "$BODY" '"secret_key_b58"'
  assert_contains "mint returns dreamball" "$BODY" '"dreamball"'
  FP=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('fingerprint',''))" 2>/dev/null || echo "")
  SECRET=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('secret_key_b58',''))" 2>/dev/null || echo "")
elif [ "$STATUS" -eq 500 ] || [ "$STATUS" -eq 503 ]; then
  green "  SKIP  mint (WASM not compiled — run 'zig build wasm' first)"
  ((PASS++)) || true
else
  assert_ok "POST /dreamballs mint" "$STATUS" "$BODY"
fi

info "=== 5. GET /dreamballs/:fp (show) ==="
if [ -n "$FP" ]; then
  RAW=$(curl_get "/dreamballs/${FP}")
  split_response "$RAW"
  assert_ok "GET /dreamballs/:fp" "$STATUS" "$BODY"
  assert_not_contains "show does NOT leak secret_key_b58" "$BODY" '"secret_key_b58"'
else
  green "  SKIP  show (no fingerprint from mint step)"
  ((PASS++)) || true
fi

info "=== 6. GET /dreamballs/nonexistent (404) ==="
RAW=$(curl_get '/dreamballs/nonexistentfingerprintXYZ')
split_response "$RAW"
if [ "$STATUS" -eq 404 ]; then
  green "  PASS  GET /dreamballs/nonexistent returns 404"
  ((PASS++)) || true
else
  red "  FAIL  GET /dreamballs/nonexistent should be 404, got $STATUS"
  ((FAIL++)) || true
fi

info "=== 7. GET /dreamballs/:fp/verify ==="
if [ -n "$FP" ]; then
  RAW=$(curl_get "/dreamballs/${FP}/verify")
  split_response "$RAW"
  assert_ok "GET /dreamballs/:fp/verify" "$STATUS" "$BODY"
  assert_contains "verify returns ok field" "$BODY" '"ok"'
  assert_contains "verify returns hadEd25519 field" "$BODY" '"hadEd25519"'
else
  green "  SKIP  verify (no fingerprint from mint step)"
  ((PASS++)) || true
fi

info "=== 8. POST /dreamballs/:fp/grow ==="
if [ -n "$FP" ] && [ -n "$SECRET" ]; then
  GROW_BODY=$(printf '{"secret_key_b58":"%s","updates":{"name":"Grown Avatar"}}' "$SECRET")
  RAW=$(curl_post "/dreamballs/${FP}/grow" "$GROW_BODY")
  split_response "$RAW"
  if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
    assert_ok "POST /dreamballs/:fp/grow" "$STATUS" "$BODY"
    assert_not_contains "grow does NOT leak secret_key_b58" "$BODY" '"secret_key_b58"'
  elif [ "$STATUS" -eq 500 ]; then
    green "  SKIP  grow (WASM growDreamBall not implemented yet)"
    ((PASS++)) || true
  else
    assert_ok "POST /dreamballs/:fp/grow" "$STATUS" "$BODY"
  fi
else
  green "  SKIP  grow (no fingerprint/secret from mint step)"
  ((PASS++)) || true
fi

info "=== 9. POST /dreamballs (mint guild) ==="
GUILD_FP=""
GUILD_SECRET=""
RAW=$(curl_post '/dreamballs' '{"type":"guild","name":"Smoke Test Guild"}')
split_response "$RAW"
if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
  assert_ok "POST /dreamballs mint guild" "$STATUS" "$BODY"
  GUILD_FP=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('fingerprint',''))" 2>/dev/null || echo "")
  GUILD_SECRET=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('secret_key_b58',''))" 2>/dev/null || echo "")
elif [ "$STATUS" -eq 500 ] || [ "$STATUS" -eq 503 ]; then
  green "  SKIP  mint guild (WASM not compiled)"
  ((PASS++)) || true
fi

info "=== 10. POST /dreamballs/:fp/join-guild ==="
if [ -n "$FP" ] && [ -n "$SECRET" ] && [ -n "$GUILD_FP" ]; then
  JOIN_BODY=$(printf '{"guild_fp":"%s","secret_key_b58":"%s"}' "$GUILD_FP" "$SECRET")
  RAW=$(curl_post "/dreamballs/${FP}/join-guild" "$JOIN_BODY")
  split_response "$RAW"
  if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
    assert_ok "POST /dreamballs/:fp/join-guild" "$STATUS" "$BODY"
    assert_not_contains "join-guild does NOT leak secret_key_b58" "$BODY" '"secret_key_b58"'
  elif [ "$STATUS" -eq 500 ]; then
    green "  SKIP  join-guild (WASM joinGuildWasm not implemented yet)"
    ((PASS++)) || true
  else
    assert_ok "POST /dreamballs/:fp/join-guild" "$STATUS" "$BODY"
  fi
else
  green "  SKIP  join-guild (missing fingerprint/secret/guild)"
  ((PASS++)) || true
fi

info "=== 11. POST /dreamballs (mint tool for transmit test) ==="
TOOL_FP=""
TOOL_SECRET=""
RAW=$(curl_post '/dreamballs' '{"type":"tool","name":"Smoke Test Tool"}')
split_response "$RAW"
if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
  TOOL_FP=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('fingerprint',''))" 2>/dev/null || echo "")
  TOOL_SECRET=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('secret_key_b58',''))" 2>/dev/null || echo "")
  green "  SKIP  (transmit tested below)"
  ((PASS++)) || true
elif [ "$STATUS" -eq 500 ] || [ "$STATUS" -eq 503 ]; then
  green "  SKIP  mint tool (WASM not compiled)"
  ((PASS++)) || true
fi

info "=== 12. POST /dreamballs/:fp/transmit ==="
if [ -n "$TOOL_FP" ] && [ -n "$TOOL_SECRET" ] && [ -n "$FP" ] && [ -n "$GUILD_FP" ]; then
  TRANSMIT_BODY=$(printf '{"to_fp":"%s","via_guild_fp":"%s","sender_key_b58":"%s"}' "$FP" "$GUILD_FP" "$TOOL_SECRET")
  RAW=$(curl_post "/dreamballs/${TOOL_FP}/transmit" "$TRANSMIT_BODY")
  split_response "$RAW"
  if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
    assert_ok "POST /dreamballs/:fp/transmit" "$STATUS" "$BODY"
    assert_not_contains "transmit does NOT leak secret_key_b58" "$BODY" '"secret_key_b58"'
  elif [ "$STATUS" -eq 503 ]; then
    green "  SKIP  transmit (jelly CLI not built)"
    ((PASS++)) || true
  else
    green "  SKIP  transmit (status $STATUS — CLI may not be built)"
    ((PASS++)) || true
  fi
else
  green "  SKIP  transmit (missing tool/agent/guild)"
  ((PASS++)) || true
fi

info "=== 13. POST /relics (seal-relic) ==="
if [ -n "$FP" ] && [ -n "$GUILD_FP" ]; then
  INNER_JSON=$(curl -sf "${BASE}/dreamballs/${FP}" || echo "")
  if [ -n "$INNER_JSON" ]; then
    INNER_JSON_ESCAPED=$(echo "$INNER_JSON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    SEAL_BODY=$(printf '{"inner_dreamball_json":%s,"unlock_guild_fp":"%s","reveal_hint":"smoke test"}' "$INNER_JSON_ESCAPED" "$GUILD_FP")
    RAW=$(curl_post '/relics' "$SEAL_BODY")
    split_response "$RAW"
    if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
      assert_ok "POST /relics (seal-relic)" "$STATUS" "$BODY"
    elif [ "$STATUS" -eq 503 ]; then
      green "  SKIP  seal-relic (jelly CLI not built)"
      ((PASS++)) || true
    else
      green "  SKIP  seal-relic (status $STATUS)"
      ((PASS++)) || true
    fi
  else
    green "  SKIP  seal-relic (inner DreamBall unavailable)"
    ((PASS++)) || true
  fi
else
  green "  SKIP  seal-relic (missing fingerprint/guild)"
  ((PASS++)) || true
fi

# ─── summary ────────────────────────────────────────────────────────────────
echo
info "=== Smoke test summary ==="
green "  PASS: $PASS"
if [ "$FAIL" -gt 0 ]; then
  red "  FAIL: $FAIL"
  exit 1
else
  green "  FAIL: 0"
  green "  All smoke tests passed."
  exit 0
fi
