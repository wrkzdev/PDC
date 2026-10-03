#!/usr/bin/env bash
# Runs the end-to-end test: real wallet engine -> gateway -> testnet node, deploying and moving an asset on a real chain.
# Needs docker with compose; the first run builds the node and wallet library (tens of minutes), later runs reuse caches.
#   utils/docker/e2e/run.sh            # exit status is the test result; test output goes to stderr
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would otherwise rewrite container paths
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$(cd "$HERE" && (pwd -W 2>/dev/null || pwd))/compose.yml")

cleanup() { "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1; }
trap cleanup EXIT

"${COMPOSE[@]}" build || exit 2
"${COMPOSE[@]}" up -d node gateway || exit 2

# The runner runs on its own so its test output (stderr) is not mixed with the engine's native logging (stdout).
"${COMPOSE[@]}" run --rm -T runner >/tmp/pdc-e2e-engine.log 2>&1
status=$?
# the test's own lines are the ones starting with "[  12s]"
grep -E '^\[ *[0-9]+s\]|E2E (PASSED|FAILED)|Unhandled|Exception|Bad state' /tmp/pdc-e2e-engine.log
echo
if [ "$status" -ne 0 ]; then
  echo "---- gateway log (method, path, status) ----"
  "${COMPOSE[@]}" logs --no-color --tail 60 gateway
  echo "---- node log tail ----"
  "${COMPOSE[@]}" logs --no-color --tail 30 node
fi
echo "end-to-end test exit status: $status (engine log: /tmp/pdc-e2e-engine.log)"
exit $status
