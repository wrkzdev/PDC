#!/usr/bin/env bash
# Runs the end-to-end test: real wallet engine -> gateway -> testnet node, deploying and moving an asset on a real chain.
# Needs docker with compose; the first run builds the node and wallet library (tens of minutes), later runs reuse caches.
#   utils/docker/e2e/run.sh            # exit status is the test result
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would otherwise rewrite container paths
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$(cd "$HERE" && (pwd -W 2>/dev/null || pwd))/compose.yml")

cleanup() { "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1; }
trap cleanup EXIT

"${COMPOSE[@]}" up --build --abort-on-container-exit --exit-code-from runner
status=$?
echo
echo "end-to-end test exit status: $status"
exit $status
