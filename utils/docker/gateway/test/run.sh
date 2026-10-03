#!/usr/bin/env bash
# End-to-end test of the public-node gateway against a mock pdcd. Needs docker and curl.
#   utils/docker/gateway/test/run.sh
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would otherwise rewrite container paths

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_HERE="$(cd "$HERE" && (pwd -W 2>/dev/null || pwd))"   # host path docker can mount
NET=pdc-gw-test-net
MOCK=pdc-gw-test-mock
GW=pdc-gw-test-gateway
IMG=pdc-gateway:test
PORT="${GATEWAY_TEST_PORT:-18080}"
URL="http://127.0.0.1:${PORT}"
FAILS=0
PASSES=0

TMPD=""
cleanup() { docker rm -f "$GW" "$MOCK" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; [ -n "$TMPD" ] && rm -rf "$TMPD"; }
trap cleanup EXIT
cleanup
TMPD="$(mktemp -d)"
TMPW="$(cd "$TMPD" && (pwd -W 2>/dev/null || pwd))"   # same dir, in a form native curl understands

pass() { PASSES=$((PASSES + 1)); echo "  ok   $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi; }

hits() { docker logs "$MOCK" 2>&1 | grep -c "\"path\": \"$1\""; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
rpc()  { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary "$1" "$URL/json_rpc"; }

echo "== build + start"
docker build -q -t "$IMG" "$HOST_HERE/.." >/dev/null || { echo "gateway image build failed"; exit 2; }
docker network create "$NET" >/dev/null
docker run -d --name "$MOCK" --network "$NET" -v "$HOST_HERE/mock_pdcd.py:/mock.py:ro" python:3.12-alpine python -u /mock.py 19211 >/dev/null
docker run -d --name "$GW" --network "$NET" -p "127.0.0.1:${PORT}:8080" \
  -e PDCD_UPSTREAM="${MOCK}:19211" -e RATE_LIGHT=50 -e RATE_HEAVY=20 "$IMG" >/dev/null

for _ in $(seq 1 40); do [ "$(code "$URL/healthz")" = "200" ] && break; sleep 0.5; done
check "healthz" "$(code "$URL/healthz")" 200

echo "== allowed plain URIs are forwarded"
check "POST /getinfo" "$(code -X POST --data '{}' "$URL/getinfo")" 200
check "/getinfo reached the daemon" "$(hits /getinfo)" 1
check "POST /sendrawtransaction" "$(code -X POST --data '{"tx_as_hex":"00"}' "$URL/sendrawtransaction")" 200
check "POST /getheight" "$(code -X POST --data '{}' "$URL/getheight")" 200

echo "== binary endpoints keep bytes intact"
EXPECTED=$(docker exec "$MOCK" python -c "import hashlib; print(hashlib.sha256(bytes(range(256))*8).hexdigest())")
printf '\x00\x01\xff\xfe' > "$TMPD/req.bin"
GOT=$(curl -s -X POST --data-binary @"$TMPW/req.bin" "$URL/getblocks.bin" | sha256sum | cut -d' ' -f1)
check "getblocks.bin response is byte-identical" "$GOT" "$EXPECTED"
BODYSHA=$(sha256sum < "$TMPD/req.bin" | cut -d' ' -f1)
curl -s -o /dev/null -X POST --data-binary @"$TMPW/req.bin" "$URL/get_o_indexes.bin"
check "binary request body forwarded intact" "$(docker logs "$MOCK" 2>&1 | grep '/get_o_indexes.bin' | grep -c "$BODYSHA")" 1

echo "== json_rpc allowlist"
check "getinfo allowed" "$(rpc '{"jsonrpc":"2.0","id":0,"method":"getinfo","params":{}}')" 200
check "get_asset_info allowed" "$(rpc '{"jsonrpc":"2.0","id":0,"method":"get_asset_info","params":{"asset_id":"00"}}')" 200
for m in submitblock submitblock2 getblocktemplate reset_transaction_pool remove_tx_from_pool decrypt_tx_details find_outs_in_recent_blocks validate_signature get_all_alias_details; do
  check "json_rpc $m refused" "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"$m\",\"params\":{}}")" 403
done
check "denied json_rpc never reached the daemon" "$(hits /json_rpc)" 2
check "duplicate method key refused" "$(rpc '{"method":"submitblock","method":"getinfo"}')" 400
check "duplicate method key refused (other order)" "$(rpc '{"method":"getinfo","method":"submitblock"}')" 400
check "escaped method key refused" "$(rpc '{"method":"submitblock","method":"getinfo"}')" 400
check "batch refused" "$(rpc '[{"method":"getinfo"}]')" 400
check "invalid json refused" "$(rpc 'not json')" 400
check "missing method refused" "$(rpc '{"params":{}}')" 400
check "inherited property name refused" "$(rpc '{"method":"constructor"}')" 403
check "GET /json_rpc refused" "$(code "$URL/json_rpc")" 405

echo "== 64-bit values pass through unchanged"
BIG='{"jsonrpc":"2.0","id":1,"method":"get_asset_info","params":{"amount":18446744073709551615}}'
BIGSHA=$(printf '%s' "$BIG" | sha256sum | cut -d' ' -f1)
rpc "$BIG" >/dev/null
check "json_rpc body forwarded byte-identical" "$(docker logs "$MOCK" 2>&1 | grep -c "$BIGSHA")" 1

echo "== control and legacy endpoints are not exposed"
for p in /start_mining /stop_mining /force_relay /set_maintainers_info.bin /getrandom_outs.bin /getrandom_outs1.bin /get_pos_details.bin /nonexistent; do
  check "POST $p refused" "$(code -X POST --data '{}' "$URL$p")" 403
done
check "none of them reached the daemon" "$(docker logs "$MOCK" 2>&1 | grep -cE '"path": "/(start_mining|stop_mining|force_relay|set_maintainers_info.bin|getrandom_outs.bin|getrandom_outs1.bin|get_pos_details.bin|nonexistent)"')" 0
check "DELETE refused" "$(code -X DELETE "$URL/getinfo")" 405

echo "== CORS"
check "preflight 204" "$(code -X OPTIONS -H 'Origin: https://wallet.example' -H 'Access-Control-Request-Method: POST' "$URL/json_rpc")" 204
check "preflight allow-origin" "$(curl -s -D - -o /dev/null -X OPTIONS -H 'Origin: https://wallet.example' "$URL/getblocks.bin" | tr -d '\r' | grep -ic '^access-control-allow-origin: \*')" 1
check "allow-origin on normal response" "$(curl -s -D - -o /dev/null -X POST --data '{}' "$URL/getinfo" | tr -d '\r' | grep -ic '^access-control-allow-origin: \*')" 1
check "preflight not forwarded" "$(hits /getblocks.bin)" 1

echo "== privacy"
check "client address not forwarded" "$(docker logs "$MOCK" 2>&1 | grep -c '"xff": "[^"]'; true)" 0
check "real-ip not forwarded" "$(docker logs "$MOCK" 2>&1 | grep -c '"real_ip": "[^"]'; true)" 0

echo "== rate limit"
# restart with a tight limit so the test does not depend on how fast this machine can spawn curl
docker rm -f "$GW" >/dev/null 2>&1
docker run -d --name "$GW" --network "$NET" -p "127.0.0.1:${PORT}:8080"   -e PDCD_UPSTREAM="${MOCK}:19211" -e RATE_LIGHT=1 -e RATE_HEAVY=1 "$IMG" >/dev/null
for _ in $(seq 1 40); do [ "$(code "$URL/healthz")" = "200" ] && break; sleep 0.5; done
CODES=$(for _ in $(seq 1 120); do curl -s -o /dev/null -w '%{http_code}
' -X POST --data '{}' "$URL/getheight"; done | sort | uniq -c | tr '
' ' ')
if echo "$CODES" | grep -q ' 429'; then pass "120 quick requests at 1 r/s get 429s ($CODES)"; else fail "no 429 under burst ($CODES)"; fi
check "healthz is not rate limited" "$(code "$URL/healthz")" 200
# the limit is per client address, taken from X-Forwarded-For when the request comes from a private network
CODES_A=$(for _ in $(seq 1 80); do curl -s -o /dev/null -w '%{http_code}
' -X POST --data '{}' -H 'X-Forwarded-For: 198.51.100.1' "$URL/getheight"; done | sort | uniq -c | tr '
' ' ')
if echo "$CODES_A" | grep -q ' 429'; then pass "forwarded client A is limited ($CODES_A)"; else fail "forwarded client A not limited ($CODES_A)"; fi
check "a different forwarded client B is not limited" "$(code -X POST --data '{}' -H 'X-Forwarded-For: 198.51.100.77' "$URL/getheight")" 200

echo
echo "passed: $PASSES  failed: $FAILS"
[ "$FAILS" -eq 0 ]
