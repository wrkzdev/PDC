# PDC Wallet (Flutter)

Desktop and web wallet for PDC that syncs from a **remote node** (no local blockchain) and can **deploy, emit and burn
confidential assets**. Plan, architecture and phases: [../docs/wallet/PLAN.md](../docs/wallet/PLAN.md).

## Status

The app, its Dart layer and tests are done and run on an **in-memory demo engine** (`MockWalletCore`): balances are fake
and nothing touches the network, and every screen says so. The real engine (the C++ wallet behind
`plain_wallet_api`, over `dart:ffi` on desktop and WebAssembly on the web) is the next phase and plugs in through
`lib/wallet/raw_wallet_api.dart`. **Do not use real funds yet.**

## Layout

| Path | What |
|---|---|
| `lib/core` | `Amount` (BigInt, uint64-safe), exact JSON codec, asset validation rules |
| `lib/node` | `NodeClient`: JSON-RPC to the node through the gateway (health, fee, asset lookup) |
| `lib/wallet` | `WalletCore` interface; `InvokeWalletCore` (wallet RPC over `RawWalletApi`); `MockWalletCore` |
| `lib/app`, `lib/ui` | controller and screens: welcome, wallet, send, assets (deploy / emit / burn), settings |
| `tool/` | `js_precision_check.dart`: runs the amount/JSON code compiled to JS under Node |

Amounts are uint64 atomic units, which exceed JavaScript's 53-bit numbers, so nothing in here uses `double`, `int` or
`jsonDecode` for money.

## Run and test

```
flutter pub get
flutter analyze
flutter test                      # 49 tests, including a full create -> deploy asset -> send widget flow
flutter run -d windows            # or linux, macos, chrome
flutter build web --release
```

Check that the money code is exact in a real JavaScript runtime (needs Node):

```
dart compile js tool/js_precision_check.dart -o /tmp/js_precision_check.js && node /tmp/js_precision_check.js
```

## Node address

Use an `https://` node, normally the public-node gateway in `../utils/docker/gateway`. Plain `http://` is only accepted
for localhost. The app asks for the node on the first screen and in Settings ("Test connection" calls `getinfo`).
