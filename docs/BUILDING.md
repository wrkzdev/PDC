# Building and cross-compiling PDC

Every build type, how to produce it, and how much of it has actually been run. Statuses used below:

- **Verified here**: built and run on the development machine for this branch (Windows 11 host, Docker Desktop with WSL2,
  Visual Studio 2022, Flutter 3.38.7 / Dart 3.10.7).
- **CI**: built by the GitHub workflows in `.github/workflows` (not re-run here).
- **Not verified**: the recipe is derived from the sources and workflows but nobody has run it. Treat it as a starting point.

## At a glance

| Target | Daemon, CLI wallet | Wallet library for Flutter (`pdc_wallet_core`) | Flutter wallet app | Qt GUI |
|---|---|---|---|---|
| Linux x86-64 | **Verified here** (Docker), CI | **Verified here**, including an end-to-end run on a testnet | **builds in Docker** with the library bundled; not run with a display | CI (Qt 5.12, AppImage) |
| Linux arm64 | Not verified (Docker buildx recipe below) | Not verified | not verified | not built |
| Windows x64 | CI (MSVC 2022), and **cross-compiled from Linux in Docker** (MinGW-w64): **verified here**, `pdcd.exe` runs on Windows | **Verified here**: the cross-compiled `pdc_wallet_core.dll` passes the real-engine check on Windows | **Verified here** (`flutter build windows` on Windows; loads the DLL and closes cleanly) | CI (MSVC + Qt, Inno Setup installer) |
| macOS (arm64) | CI (`macos-14`) | not built | not built | CI (ad-hoc signed) |
| Android, iOS | not built | static libraries via the mobile configuration, not verified | platform folders not created yet | n/a |
| Web | n/a | WebAssembly build **not started** | **Verified here** (builds in Docker, `flutter build web`); runs on the demo engine | n/a |

Docker builds Linux natively and Windows x64 by cross-compiling with MinGW-w64, plus the Flutter web and Linux desktop apps.
What Docker cannot do: the Flutter Windows and macOS desktop apps (Flutter does not cross-compile them) and anything for
macOS (Apple's SDK is only licensed for Macs). Those are built natively on their own hosts; the steps are below.

## Versions that matter

| Component | Version in CI | Notes |
|---|---|---|
| Boost | 1.84.0 (Linux CLI, macOS, Windows, Docker); the Linux GUI job uses 1.80.0 | built with `system,filesystem,thread,date_time,chrono,regex,serialization,atomic,program_options,locale,timer,log` |
| OpenSSL | 1.1.1w (Linux, Windows, Docker); `openssl@3` static on macOS | 1.1.1 is end of life; Boost.Asio 1.84 and the daemon are built against it. Plan a migration |
| CMake | 3.15 or newer (Docker image uses the distro's 3.22) | |
| Compiler | GCC 11 (Ubuntu 22.04), MSVC 2022, Apple clang | C++17 |
| Qt (GUI only) | 5.12.12 in CI (README says 5.11.2) | needs the WebEngine module |
| Flutter | 3.38.7, Dart 3.10.7 | for the Flutter wallet |

## Docker (reproducible Linux builds)

**One command builds the whole amd64 release set** (Linux node and tools, Windows node, tools and wallet DLL, the wallet library,
the Flutter web wallet and the Flutter Linux desktop wallet) into `./dist`:

```
./utils/docker/build-all.sh                  # or: docker buildx bake   (targets are defined in docker-bake.hcl)
./utils/docker/build-all.sh windows-x64      # one target
./utils/docker/build-all.sh check            # all tests
JOBS=6 TESTNET=TRUE DIST=/data/pdc ./utils/docker/build-all.sh
```

`build-all.sh` builds the targets one after another on purpose: several C++ builds at once can exhaust Docker's memory
(Docker Desktop died that way on the development machine). `JOBS=0` (the default) sizes the parallelism from the CPUs and the
free memory. The same builds without bake are listed below.

Everything below runs from the repository root, with submodules checked out
(`git submodule update --init --recursive`). `utils/docker/Dockerfile` builds the source tree it is run from; it never
clones. Downloads are verified against pinned SHA-256 values.

| Command | Result |
|---|---|
| `docker build -f utils/docker/Dockerfile -t pdc-node .` | runtime image with `pdcd` and `simplewallet` (static build, non-root, runs with `--no-console`) |
| `docker build -f utils/docker/Dockerfile --target artifacts -o out .` | `pdcd`, `simplewallet`, `connectivity_tool` in `./out` |
| `docker build -f utils/docker/Dockerfile --target tests .` | builds and runs the unit tests (546 pass on this branch) |
| `docker build -f utils/docker/Dockerfile --target walletlib-artifacts -o out .` | `libpdc_wallet_core.so` plus the Boost and OpenSSL libraries it needs, relocatable (`$ORIGIN` rpath) |
| `docker build -f utils/docker/Dockerfile --target walletlib-dart-check .` | drives that library from the Flutter wallet's Dart code, offline |
| `docker build -f utils/docker/Dockerfile --target win-artifacts -o out/windows .` | **Windows x64**, cross-compiled with MinGW-w64: `pdcd.exe`, `simplewallet.exe`, `connectivity_tool.exe`, `pdc_wallet_core.dll`, all statically linked |
| `docker build -f utils/docker/Dockerfile --target wallet-web-artifacts -o out/web .` | the Flutter web wallet (static files) |
| `docker build -f utils/docker/Dockerfile --target wallet-linux-artifacts -o out/wallet-linux .` | the Flutter Linux desktop wallet with the native library beside it |
| `docker build -f utils/docker/Dockerfile --target wallet-flutter-tests .` | Flutter analyzer and the 65 Flutter tests |
| `--build-arg TESTNET=TRUE` | testnet binaries (other ports, network id and fork schedule) for any of the above |
| `--build-arg JOBS=8`, `--build-arg PDC_ENGINE=native`, `GTEST_FILTER='pattern*'` | limit parallelism, narrow the test run |
| `utils/docker/e2e/run.sh` | the end-to-end test: testnet node + gateway + real wallet engine (see `utils/docker/README.md`) |

The first build compiles Boost and OpenSSL (tens of minutes); BuildKit caches them and a ccache mount keeps later rebuilds
short. Budget **20 GB or more of disk** for the build cache and images.

### Linux arm64 (not verified)

Nothing in the Dockerfile is architecture specific (Boost and OpenSSL are built from source for the target), and QEMU
emulation of arm64 works on the development machine, so:

```
docker buildx create --use                      # once
docker buildx build --platform linux/arm64 -f utils/docker/Dockerfile --target artifacts -o out-arm64 .
docker buildx build --platform linux/amd64,linux/arm64 -f utils/docker/Dockerfile -t pdc-node .   # both, as a manifest
```

Under emulation a full build of this size takes many hours. For releases build each architecture on a native arm64 runner
and merge the manifests with `docker buildx imagetools create`. RandomARQ's JIT supports arm64; on Apple Silicon the
code falls back to the interpreter (see `select_rx_flags` in `src/currency_core/basic_pow_helpers.cpp`). The release CI has
hooks for an `aarch64` label (`strip` is skipped) but no aarch64 job.

## Linux without Docker (CI, verified through Docker)

Mirror `.github/workflows/main-cli.yml`:

```
sudo apt-get install -y build-essential python3-dev curl autotools-dev libicu-dev libbz2-dev cmake git zlib1g-dev ccache
# Boost 1.84 and OpenSSL 1.1.1w built from source, see the workflow or the Dockerfile for the exact steps
mkdir build && cd build
cmake -D BOOST_ROOT=$HOME/boost_1_84_0 -D OPENSSL_ROOT_DIR=$HOME/openssl \
      -D BUILD_GUI=OFF -D STATIC=true -D CMAKE_BUILD_TYPE=Release -D BUILD_TESTS=OFF ..
make -j"$(nproc)" daemon simplewallet connectivity_tool      # binaries land in build/src (pdcd, simplewallet, ...)
```

Unit tests: configure with `-D BUILD_TESTS=ON` and `make unit_tests && ./tests/unit_tests`. The `coretests` and
`functional_tests` targets exist but are not part of CI or of anything verified here.

## Windows x64

- **Daemon and CLI wallet (CI):** Visual Studio 2022 (generator `Visual Studio 17 2022 -A x64`), OpenSSL 1.1.1w built from
  source with `perl Configure VC-WIN64A no-asm`, prebuilt Boost 1.84 for MSVC 14.3 from boost.teeks99.com, `STATIC=OFF`, then
  `MSBuild Pdc.sln /p:Configuration=Release`. See `.github/workflows/main-cli.yml` (job `windows_build`). Local scripts:
  `utils/configure_win64_msvs2022_gui.cmd` with paths set in `utils/configure_local_paths.cmd`.
- **Qt GUI (CI):** `.github/workflows/main.yml`; the installer is built with Inno Setup (`utils/setup_64.iss`). Windows
  installers are not Authenticode-signed.
- **Flutter wallet app (verified here):** `cd wallet-flutter && flutter build windows --release` produces
  `build\windows\x64\runner\Release\pdc_wallet.exe` (needs Visual Studio's "Desktop development with C++").
- **Cross-compiled from Linux (verified here):** `docker build -f utils/docker/Dockerfile --target win-artifacts -o out/windows .`
  produces `pdcd.exe`, `simplewallet.exe`, `connectivity_tool.exe` and `pdc_wallet_core.dll` with MinGW-w64 (posix threads, GCC 10),
  Boost 1.84 and OpenSSL 1.1.1w cross-compiled in their own cached stages, everything statically linked, so there are no
  DLLs to ship. On Windows 11 the cross-compiled `pdcd.exe` reports its version and the mainnet genesis, loads the chain
  snapshot and answers RPC, and the DLL passes `wallet-flutter/tool/real_engine_check` (create, reopen, wrong password,
  restore reproducing the address, clean failures). Getting there needed small, platform-neutral source fixes (listed in the
  commit message): `execinfo.h` only off Windows, the MSVC-only `ui64` literal in `ecrypt-config.h`, the case of `psapi.h`, no
  LTO with MinGW (internal compiler error), the Windows system libraries that MSVC pulls in through `#pragma comment(lib)`, and
  `-municode` for `simplewallet`'s `wmain`. The toolchain file is `utils/toolchains/mingw-w64-x86_64.cmake`. These are not
  code-signed.
- **Wallet library with MSVC:** not built; the MinGW DLL above is the one that was verified.
- **Flutter app with the DLL:** build the app on Windows (Flutter cannot cross-compile desktop apps), then copy the DLL beside the
  executable: `flutter build windows --release --dart-define=PDC_ENGINE=native` and
  `copy dist\windows-x64\pdc_wallet_core.dll wallet-flutteruild\windowsdunner\Release\`. Verified: the app loads the
  DLL and closes in under a second.
- **Exiting:** the engine must be stopped with `pdc_wallet_shutdown()` (the app does it when it is asked to exit). Without it a
  process using the DLL finished its work and never ended, because the engine joined its threads in a static destructor under
  the Windows loader lock.

Windows build hygiene that cost time here: keep Docker's data and the Flutter pub cache off a nearly full `C:` drive (see
"Troubleshooting"), and use `MSYS_NO_PATHCONV=1` when running the shell scripts under Git Bash.

## macOS

- **Daemon and CLI wallet (CI):** `macos-14` (Apple Silicon). `brew install ccache cmake openssl@3`, Boost 1.84 built static
  with `boost.locale.icu=off`, OpenSSL linked statically, `-D BUILD_GUI=OFF -D CMAKE_BUILD_TYPE=Release`. The workflow fails
  the build if a binary still links a non-portable Boost or OpenSSL path (`otool -L` check).
- **Qt GUI (CI):** `utils/build_script_mac_osx.sh` and the `main.yml` job; ad-hoc signed only
  (`utils/macos_adhoc_codesign.sh`), so Gatekeeper warns. A Developer ID signature and notarization are not set up.
- **Flutter app, wallet library (not built):** `flutter build macos` needs a Mac; the library would be
  `libpdc_wallet_core.dylib` (the app looks beside the executable, in `Contents/Frameworks`, or at `PDC_WALLET_CORE_LIB`),
  with Boost/OpenSSL bundled and `@loader_path` rpaths instead of `$ORIGIN`.
- **Intel/universal binaries:** not covered by CI (arm64 runner only).

## Android and iOS (not verified)

The root `CMakeLists.txt` already switches to the remote-only wallet configuration (`MOBILE_WALLET_BUILD`) when
`CMAKE_SYSTEM_NAME` is `Android` or `iOS`, and `src/CMakeLists.txt` then builds only the static libraries
`wallet`, `currency_core`, `crypto`, `common` and `zlibstatic` and installs them. What is missing here:

- Boost and OpenSSL built for each mobile ABI, and the NDK / Xcode toolchain files;
- a shared wrapper per platform exposing `src/wallet_core_lib/pdc_wallet_core.h` (on iOS a static library linked into the
  app is the norm, with `DynamicLibrary.process()` instead of `open`);
- `flutter create --platforms=android,ios .` in `wallet-flutter`, which has not been run (only desktop and web exist).

## Web

- **Flutter app (verified here):** `cd wallet-flutter && flutter build web --release` (about 30 MB of output). It runs on the
  demo engine; `dart:ffi` does not exist in the browser, so the web build never loads the native library.
- **Engine as WebAssembly (not started):** compile `wallet2` in the remote-only configuration with Emscripten (installed on
  the development machine), replace the epee HTTP client behind `i_core_proxy` with `fetch`, persist wallets in IndexedDB, and
  drop RandomX/ethash. The plan and the obstacles are in `docs/wallet/PLAN.md`.
- **Node access from a browser:** the daemon has no CORS or TLS. Serve it through `utils/docker/gateway` (see
  `utils/docker/README.md`).

## Qt GUI

`-D BUILD_GUI=ON -D CMAKE_PREFIX_PATH=<Qt>` (Qt 5.12 with WebEngine in CI; Qt 6 branches exist in `CMakeLists.txt` and
`main.cpp`). The user interface lives in the `src/gui/qt-daemon/layout` submodule (`pdc_ui`) and must be checked out. Linux
releases are an AppImage built with `linuxdeployqt` fetched from its "continuous" release, which is unpinned; pin it before
relying on reproducible GUI builds. The Flutter wallet is meant to replace this GUI.

## The wallet library for the Flutter app

`-D BUILD_WALLET_CORE_LIB=ON` (separate build directory) builds only `pdc_wallet_core` with the remote-only configuration. The
Docker target `walletlib-artifacts` does it and bundles the shared Boost and OpenSSL libraries beside it with an `$ORIGIN`
rpath, so the folder can be copied anywhere and loaded without `LD_LIBRARY_PATH`. The smoke test
(`src/wallet_core_lib/smoke_test.c`) loads it through `dlopen`, creates a wallet offline and checks the replies.

The Flutter app selects the engine at build time: `--dart-define=PDC_ENGINE=demo` (default, fake balances) or `native`
(loads the library from beside the executable or from `PDC_WALLET_CORE_LIB`). The `native` engine is opt-in until the app UI
itself has been exercised on it.

## Which tests prove what

| Check | Command | Proves |
|---|---|---|
| Unit tests | `docker build -f utils/docker/Dockerfile --target tests .` | 546 C++ tests incl. the RandomARQ epoch cache and seed file parser |
| Gateway | `utils/docker/gateway/test/run.sh` | allowlist, CORS, rate limits, GET/POST JSON-RPC, binary integrity (51 checks) |
| Flutter | `cd wallet-flutter && flutter analyze && flutter test` | amounts/JSON exactness, node client, engine adapter, FFI binding against a stub library, full UI flow (64 tests) |
| JS precision | `dart compile js wallet-flutter/tool/js_precision_check.dart -o /tmp/p.js && node /tmp/p.js` | uint64 values stay exact in a JavaScript runtime |
| Real engine, offline | `docker build -f utils/docker/Dockerfile --target walletlib-dart-check .` | create, reopen, wrong password, restore reproduces the address, clean failures |
| Real engine, on a chain | `utils/docker/e2e/run.sh` | mining, deploy, send, emit, burn, add asset by id, through the gateway |

`.github/workflows/tests.yml` runs the unit tests and the gateway test on every push. The end-to-end test is run by hand.

## Troubleshooting

- **`version 'GLIBC_2.34' not found` when running a Linux binary on another machine.** The binaries need at least the glibc of
  the image they were built on (Ubuntu 22.04 = glibc 2.35, so they need 2.34). Build on an older base and they run on it and
  anything newer: `docker build -f utils/docker/Dockerfile --build-arg UBUNTU_VERSION=20.04 --target artifacts -o dist/linux-amd64-ubuntu20 .`
  (or `UBUNTU_VERSION=20.04 docker buildx bake linux-amd64`). Verified: the 20.04 build needs glibc 2.29 at most and runs on
  Ubuntu 20.04 and 22.04; the 22.04 build fails on 20.04 with exactly that message. The wallet library and the Flutter Linux
  app take the same argument but have not been built on 20.04 yet.
- **Docker says "read-only file system", builds die with `exit code 134` or ccache errors.** The disk holding Docker's data is
  full. Docker Desktop on WSL2 keeps it in `docker_data.vhdx`; on this machine it grew past 14 GB on `C:`. Move it: quit
  Docker Desktop, `wsl --shutdown`, copy the `...\AppData\Local\Docker\wsl` folder to a bigger drive, set
  `CustomWslDistroDir` in `%APPDATA%\Docker\settings-store.json` to that folder, start Docker Desktop and check
  `docker system df` still lists your images before deleting the old file.
- **The node container exits immediately.** The daemon reads commands from stdin and stops when it is closed. Use
  `--no-console` (the image does by default).
- **Shell scripts rewrite `/paths` under Git Bash.** Set `MSYS_NO_PATHCONV=1`.
- **Shell scripts fail with `\r`.** They must have LF endings; `.gitattributes` enforces it for `*.sh` and `utils/docker`.
- **A new wallet answers `BUSY`.** Normal during its first refresh; the Flutter adapter retries for about a minute.
- **A wallet cannot build a transaction on a brand-new chain (engine error `-4`).** Confidential transactions reference 15
  decoy outputs; wait for more blocks.
- **`flutter` writes to `C:` and fills it.** Set `PUB_CACHE`, `TEMP` and `TMP` to another drive for the session.

## Releasing

Build every platform on its own runner, then run the manual **Release checksums** workflow for the tag: it publishes
`SHA256SUMS` (and `SHA256SUMS.asc` when the `RELEASE_GPG_PRIVATE_KEY` secret is set). Record who holds the signing and
network authority keys in `SECURITY.md` first.
