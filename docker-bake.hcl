# One entry point for every Docker build of PDC.  Run from the repository root (submodules checked out):
#
#   docker buildx bake                      # = group "default": the amd64 release set into ./dist
#   docker buildx bake check                # tests only, no files written
#   docker buildx bake windows-x64          # a single target
#   docker buildx bake all --set '*.args.JOBS=6'
#   docker buildx bake --print              # show what would be built
#
# Variables can be overridden on the command line:  TESTNET=TRUE docker buildx bake windows-x64
# See docs/BUILDING.md for what each target contains and how far it has been verified.

variable "TESTNET"    { default = "FALSE" }  # TRUE builds testnet binaries
variable "PDC_ENGINE" { default = "demo" }   # Flutter apps: "demo" (fake balances) or "native" (bundled wallet library)
variable "JOBS"       { default = "0" }      # 0 = size parallel jobs from the CPUs and free memory
variable "DIST"       { default = "dist" }   # output folder

target "_common" {
  context    = "."
  dockerfile = "utils/docker/Dockerfile"
  args = {
    TESTNET    = TESTNET
    PDC_ENGINE = PDC_ENGINE
    JOBS       = JOBS
  }
}

# ---- node, wallet and tools ---------------------------------------------------------------------------

target "linux-amd64" {                       # pdcd, simplewallet, connectivity_tool
  inherits  = ["_common"]
  target    = "artifacts"
  platforms = ["linux/amd64"]
  output    = ["type=local,dest=${DIST}/linux-amd64"]
}

target "linux-arm64" {                       # NOT VERIFIED: needs a native arm64 builder, QEMU takes many hours
  inherits  = ["_common"]
  target    = "artifacts"
  platforms = ["linux/arm64"]
  output    = ["type=local,dest=${DIST}/linux-arm64"]
}

target "windows-x64" {                       # pdcd.exe, simplewallet.exe, connectivity_tool.exe, pdc_wallet_core.dll (MinGW-w64)
  inherits  = ["_common"]
  target    = "win-artifacts"
  platforms = ["linux/amd64"]                # the build host; the output is Windows x64
  output    = ["type=local,dest=${DIST}/windows-x64"]
}

target "image" {                             # runtime image for running a node (loaded into the local Docker)
  inherits = ["_common"]
  target   = "runtime"
  tags     = ["pdc-node:latest"]
  output   = ["type=docker"]
}

# ---- wallet library for the Flutter app ---------------------------------------------------------------

target "walletlib-linux-amd64" {             # libpdc_wallet_core.so + Boost/OpenSSL libraries, relocatable
  inherits  = ["_common"]
  target    = "walletlib-artifacts"
  platforms = ["linux/amd64"]
  output    = ["type=local,dest=${DIST}/wallet-lib-linux-amd64"]
}

# ---- Flutter wallet (GUI and web) ---------------------------------------------------------------------

target "wallet-web" {                        # static web app
  inherits  = ["_common"]
  target    = "wallet-web-artifacts"
  platforms = ["linux/amd64"]
  output    = ["type=local,dest=${DIST}/wallet-web"]
}

target "wallet-linux-amd64" {                # Linux desktop app with the native library beside it
  inherits  = ["_common"]
  target    = "wallet-linux-artifacts"
  platforms = ["linux/amd64"]
  output    = ["type=local,dest=${DIST}/wallet-linux-amd64"]
}

target "wallet-linux-arm64" {                # NOT VERIFIED (see linux-arm64)
  inherits  = ["_common"]
  target    = "wallet-linux-artifacts"
  platforms = ["linux/arm64"]
  output    = ["type=local,dest=${DIST}/wallet-linux-arm64"]
}

# ---- checks (nothing is written; a failing test fails the build) --------------------------------------

target "check-unit-tests" {
  inherits = ["_common"]
  target   = "tests"
  output   = ["type=cacheonly"]
}

target "check-flutter" {
  inherits = ["_common"]
  target   = "wallet-flutter-tests"
  output   = ["type=cacheonly"]
}

target "check-wallet-engine" {               # the real wallet library driven by the Flutter wallet's Dart code, offline
  inherits = ["_common"]
  target   = "walletlib-dart-check"
  output   = ["type=cacheonly"]
}

# ---- groups ---------------------------------------------------------------------------------------------

group "default" {                            # the whole amd64 release set
  targets = ["linux-amd64", "windows-x64", "walletlib-linux-amd64", "wallet-web", "wallet-linux-amd64"]
}

group "check" {
  targets = ["check-unit-tests", "check-flutter", "check-wallet-engine"]
}

group "arm64" {                              # not verified
  targets = ["linux-arm64", "wallet-linux-arm64"]
}

group "all" {
  targets = ["default", "check"]
}
