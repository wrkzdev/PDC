#!/usr/bin/env bash
# Builds the PDC artifacts with Docker, one target after the other (building them in parallel can exhaust Docker's memory).
#   utils/docker/build-all.sh                 # the amd64 release set into ./dist
#   utils/docker/build-all.sh windows-x64     # just some targets (see docker-bake.hcl)
#   utils/docker/build-all.sh check           # run all the tests
#   DIST=/data/pdc-dist JOBS=6 TESTNET=TRUE utils/docker/build-all.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

[ -f contrib/randomx/CMakeLists.txt ] || { echo "submodules are missing: git submodule update --init --recursive" >&2; exit 2; }

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=(linux-amd64 windows-x64 walletlib-linux-amd64 wallet-web wallet-linux-amd64)
fi

# bake refuses to write outside the project folder unless allowed: grant exactly the DIST folder if one is given
extra=()
if [ -n "${DIST:-}" ]; then
  mkdir -p "$DIST"
  extra+=(--allow "fs.write=${DIST}")
fi

# a group name (default, check, all, arm64) is expanded by bake itself, so it is built as one invocation
for t in "${targets[@]}"; do
  echo "================ $t ================"
  docker buildx bake "${extra[@]}" "$t"
done

echo
echo "done. outputs are under ${DIST:-dist}/"
