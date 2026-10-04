# PDC wallets: desktop and web, remote node, asset deployment

Status: phase 1 and the Dart layer of phase 3 exist on this branch (see "What is built"). The native/WebAssembly engine
is the next piece. Everything here was checked against the source in this repository; unverified points are listed at
the end.

## Goals

- One Flutter code base for a desktop wallet (Windows, macOS, Linux) and a browser wallet, later mobile.
- **No local blockchain.** The wallet syncs from a remote PDC node.
- Create/restore a wallet, receive, send, history, and the full life cycle of a confidential asset: **deploy, emit,
  burn** (and later transfer ownership).
- Keys and signing stay on the user's device. A node operator can see what a wallet asks for, never its keys.
- No consensus change: nothing in this plan touches consensus code or constants.

Non-goals for the first release: staking/mining from the wallet, escrow/marketplace/atomic swaps, hardware wallets.

## Architecture

```
 Flutter UI (lib/ui)                     one code base: desktop, web, later mobile
        |
 WalletController (lib/app)              app state
        |
 WalletCore  (lib/wallet/wallet_core.dart)        the boundary; the UI only knows this
   |- MockWalletCore      in-memory demo engine, for UI work and tests (never real funds)
   '- InvokeWalletCore     maps calls to wallet RPC JSON  --->  RawWalletApi (string in / string out)
                                                                  |- desktop/mobile: dart:ffi  -> native library
                                                                  '- web:            dart:js_interop -> WebAssembly
                                                                      both are the same C++: wallet2 in remote-only mode
 NodeClient (lib/node)  JSON-RPC to the node, for health, fees and asset lookups (pure Dart, works in the browser)

 desktop / browser  --HTTPS-->  Caddy (TLS)  -->  gateway (nginx: allowlist, CORS, rate limits)  -->  pdcd RPC (127.0.0.1)
```

### Why the C++ wallet is reused instead of rewritten

A transaction here is a Zarcanum transaction: CLSAG ring signatures, Bulletproof+ range proofs, asset surjection and
ownership proofs, decoy selection, and `wallet2`'s scanning and key-image logic. Getting any of it subtly different from
the node's rules produces transactions the network rejects or, worse, that leak information. The existing wallet already
does it correctly, so the plan reuses it behind a small boundary and tests the boundary heavily.

- `src/wallet/plain_wallet_api.h` is already a string-in/string-out API (`init`, `generate`, `restore`, `open`,
  `invoke`, `get_wallet_status`, ...), built for the mobile wallets. `invoke` takes a complete wallet-RPC JSON-RPC
  request, so every wallet RPC method (`getbalance`, `transfer`, `deploy_asset`, `emit_asset`, `burn_asset`,
  `get_recent_txs_and_info2`, ...) is available without new C++ API surface.
- `-DMOBILE_WALLET_BUILD` (set automatically for iOS/Android in `CMakeLists.txt`) compiles out the core, p2p and the
  node RPC server: a remote-only wallet. A desktop remote-only library is the same configuration.
- `wallet2` is not coupled to blockchain storage: it reaches the node through `i_core_proxy`
  (`default_http_core_proxy`, an epee HTTP client).

## Remote node access

The daemon RPC has no authentication, TLS, CORS or restricted mode and exposes node-control calls, so wallets must not be
pointed at it directly. `utils/docker/gateway` (built on this branch, 48 end-to-end checks) puts an allowlist in front:

| Needed by a wallet | Forwarded |
|---|---|
| `getinfo`, `getheight`, `gettransactions`, `sendrawtransaction` | yes |
| `getblocks.bin`, `get_o_indexes.bin`, `getrandom_outs3.bin`, `get_tx_pool.bin`, `check_keyimages.bin` | yes |
| `/json_rpc`: getinfo, getblockcount, header lookups, `getrandom_outs3`, `get_current_core_tx_expiration_median`, `get_est_height_from_date`, `get_asset_info`, `get_assets_list`, alias lookups, `get_pool_info`, `get_tx_details` | yes |
| mining, `submitblock*`, `getblocktemplate`, `set_maintainers_info.bin`, pool reset/removal, `force_relay` | no |
| `decrypt_tx_details` (takes a tx secret key), `find_outs_in_recent_blocks` (takes the view key) | no, they hand secrets to the node |

Open points:

- **TLS.** `default_http_core_proxy` speaks plain HTTP only. HTTPS to a remote node therefore terminates at a reverse proxy
  (the Caddy profile). The Flutter app accepts both `http://` and `https://` and warns about plain http; note that the engine's node client ignores the scheme, so `https://` to a node without TLS in front still travels in the clear.
- **Sync cost.** The node has no server-side scanning, view tags or compact blocks: a wallet downloads every block through
  `getblocks.bin` (up to 4000 per call) and trial-decrypts outputs. Fine on desktop, heavy in a browser. Mitigations that
  need no consensus change: restore height (`get_est_height_from_date`), a wallet-side checkpoint of the scan state, and
  later an optional indexer service. This is the main risk for the web wallet.
- **Privacy.** A remote node sees block ranges and output indexes requested. The UI says so and recommends your own node.

## Asset deployment

All of it exists in `wallet2` and the wallet RPC; the work is UI and safeguards.

| Operation | Wallet RPC | Notes |
|---|---|---|
| Deploy | `deploy_asset` | descriptor + destinations; the wallet sets `owner` to its own key and the initial supply is what the destinations receive |
| Emit | `emit_asset` | owner only, up to `total_max_supply` |
| Burn | `burn_asset` | public burn |
| Update / transfer ownership | `update_asset` | later phase |

Rules enforced client-side (mirroring the node, `lib/core/asset_rules.dart`): ticker `[A-Za-z0-9]{1,14}`, full name
`[A-Za-z0-9.,:!?\-() ]{0,400}`, decimal places 0..18, `0 < total_max_supply <= 2^64-1`, initial supply `<=` maximum. Fee:
the ordinary 0.01 PDC (`TX_DEFAULT_FEE`); there is no separate registration fee in the code. An asset operation needs at
least one confidential output, so the wallet needs spendable PDC. Wallets hide assets that are not on the whitelist
(`WALLET_ASSETS_WHITELIST_URL`) from the balance unless added as custom assets, so the UI must offer "add by asset id".

**Amounts are uint64.** They do not fit a JavaScript number (53 bits) or a signed Dart `int`. The Dart layer uses `BigInt`
(`Amount`) and its own JSON codec (`json_exact.dart`) that never rounds integers. This is covered by unit tests.

## Security model

- Seed and keys exist only inside the engine on the user's device; the Dart layer sees addresses, balances and tx ids.
  The recovery phrase is shown once, behind an acknowledgement.
- Wallet files are encrypted by the engine with the user's password. Desktop: app data directory. Web: IndexedDB
  (the engine's virtual file system), never `localStorage`.
- Browser wallet: strict Content-Security-Policy, no third-party scripts or fonts, no analytics, dependencies pinned and
  the WASM binary built reproducibly in CI with a published hash. A browser wallet is exposed to XSS and supply-chain
  attacks in a way a desktop app is not; the first release carries that warning.
- Every spend shows a confirmation with amount, asset, destination and fee. Destructive asset actions say they are
  irreversible.
- The demo engine shows a banner on every screen and is never selected in a release build.

## Phases

| # | Deliverable | Exit criteria | State |
|---|---|---|---|
| 0 | Node hardening, seeds, Docker, CI | unit tests and gateway tests green in CI | done on this branch, CI not yet run (see below) |
| 1 | Public-node gateway + compose | `utils/docker/gateway/test/run.sh` passes | done |
| 2 | Native engine: C ABI over `plain_wallet_api`, remote-only library, CMake target, CI build for Windows/Linux/macOS | `pdc_wallet_core` loads from Dart, create/open/getbalance against a testnet node | Linux library built and verified, including a full run on a local testnet (see below); Windows/macOS builds not done |
| 3 | Flutter desktop app on the real engine | create, restore, receive, send, history on testnet | FFI binding done and tested; opt-in with `--dart-define=PDC_ENGINE=native`; the app UI itself has not been run on the native engine |
| 4 | Asset screens on the real engine | deploy, emit, burn on testnet with two wallets | engine calls verified end to end on a local testnet (see below); UI not yet run on the real engine |
| 5 | Web: engine compiled to WebAssembly (Emscripten), fetch-based `i_core_proxy`, IndexedDB storage, scan checkpoints | create and send from a browser against the gateway | not started; the Dart side already compiles for web |
| 6 | Mobile (the same engine, `MOBILE_WALLET_BUILD`), signing/packaging, releases with checksums | store builds | not started |

Phase 5's hard parts, from reading the sources: wallet2 pulls in Boost (serialization, program_options, filesystem)
and Boost.Asio, which need a WASM-friendly transport (replace the epee HTTP client behind `i_core_proxy` with JS `fetch`),
an in-memory/IndexedDB file layer, and a build that drops RandomX/ethash (only needed for mining). Expect this phase to
dominate the schedule; phases 2-4 do not depend on it.

## Verified against the real engine (offline, Linux)

`docker build -f utils/docker/Dockerfile --target walletlib-dart-check .` builds the wallet in its remote-only
configuration (`-D BUILD_WALLET_CORE_LIB=ON`) as `libpdc_wallet_core.so` with its Boost/OpenSSL libraries bundled and an
`$ORIGIN` rpath, smoke-tests it through `dlopen` with no library path set, then drives it from the Flutter wallet's own Dart
code. With the node address pointing nowhere it confirms:

- create a wallet: a 26-word recovery phrase (not 24), a `Px...` address, a zero native balance listed as `PDC` with 12
  decimals and asset id `d6329b5b...498a`, empty history;
- close and reopen: same address; wrong password refused (`WRONG_PASSWORD`); opening an open wallet refused
  (`ALREADY_EXISTS`);
- restore from the phrase: the same address; an invalid phrase refused (`WRONG_SEED`);
- spending, deploying an asset or burning an unknown asset without funds fail cleanly with engine codes
  (`WALLET_RPC_ERROR_CODE_NOT_ENOUGH_MONEY`, ...), which the app maps to plain language;
- the reply shapes `InvokeWalletCore` parses (`getaddress`, `getbalance`, wallet status, `init`'s `return_code`) are what
  the engine really returns.

## Verified end to end on a real chain

`utils/docker/e2e/run.sh` starts a testnet `pdcd` (offline, with its clock accelerated 60x by libfaketime so the 120 s block
target is a couple of seconds), the production gateway, and a runner that drives the real wallet engine through the
wallet's Dart code, syncing **through the gateway**. It mines to the wallet, then:

- deploys an asset (`TST`, 4 decimals, 1,000,000 maximum, 1,000 initial): the node reports the exact ticker, name, decimals,
  maximum and current supply and a non-zero owner, and the asset is in the node's asset list;
- sends 25.5 TST to a second wallet, which only lists it after `addCustomAsset` (the engine hides assets that are not
  whitelisted or owned) and then shows exactly 25.5;
- emits 500 more (node supply 1,500), burns 100 (node supply 1,400); the maximum is unchanged;
- refuses an invalid ticker client-side, and a non-owner emitting.

What running it against a real chain found and fixed:

- the wallet engine sends JSON-RPC as `GET` with a body; the gateway rejected that (405) and now accepts GET and POST;
- every wallet call answers `BUSY` during a new wallet's first refresh; the adapter now retries with a bounded backoff;
- received assets are invisible until added by id, and the whitelist is reset on restore: the app has "add asset by id" and
  must remember the ids (not done yet) to re-add them after a restore;
- the daemon stops itself when its stdin closes; the image now starts with `--no-console` (the compose file needed this);
- confidential transactions need 15 decoy outputs, so a very young chain refuses them with engine error `-4`; the app
  explains it and the harness waits for chain height.

Still open: the Flutter UI running on the native engine, restore-and-rescan timing on a long chain, and the same flow on
Windows and macOS builds of the library.

## What is built on this branch

- `wallet-flutter/`: Flutter app (`lib/core`, `lib/node`, `lib/wallet`, `lib/app`, `lib/ui`) with 49 passing tests
  (exact JSON/amounts, asset rules, node client against a fake HTTP server, the engine adapter against a fake wallet
  API using the real RPC shapes, and a full widget flow: create wallet, deploy asset, send it).
- The engine adapter's request/response shapes were read from the C++ structs (`wallet_public_structs_defs.h`,
  `core_rpc_server_commands_defs.h`), not guessed; they are still to be confirmed against a live wallet in phase 2.

## Unverified / to confirm in phase 2

- Replies of the calls that need a synced, funded wallet (`transfer`, `deploy_asset`, `emit_asset`, `burn_asset`, history with
  entries); the offline calls were checked against the real engine (see above).
- Whether the whitelist loader verifies `WALLET_ASSETS_WHITELIST_VALIDATION_PUBLIC_KEY`; it appeared not to.
- WASM feasibility of the full `wallet2` (no prototype yet; the plan isolates it to phase 5).
- `get_wallet_status` `progress` semantics: the adapter derives progress from wallet and daemon heights instead (the engine
  reports `progress: 0` and both heights 0 when it has no node).
- Packaging: the Linux bundle links shared Boost/OpenSSL 1.1.1 next to the library; Windows and macOS builds and a static
  OpenSSL option are still to do.
