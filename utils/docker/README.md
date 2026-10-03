# PDC with Docker

All platforms and build types, including cross-compiling, are covered in [../../docs/BUILDING.md](../../docs/BUILDING.md).

Everything here builds the source tree you are standing in, so a branch can be tested exactly as it is.
Clone with submodules first (`git clone --recursive`, or `git submodule update --init --recursive`).

## Images

Run from the repository root:

| Command | Result |
|---|---|
| `docker build -f utils/docker/Dockerfile -t pdc-node .` | runtime image with `pdcd` and `simplewallet` (static build, non-root user) |
| `docker build -f utils/docker/Dockerfile --target tests -t pdc-tests .` | builds and runs the unit tests; the build fails if a test fails |
| `docker build -f utils/docker/Dockerfile --target artifacts -o out .` | writes `pdcd`, `simplewallet`, `connectivity_tool` to `./out` |

Boost 1.84 and OpenSSL 1.1.1w (the versions the release CI uses) are downloaded and verified against pinned SHA-256
values; override them with `--build-arg` (see the top of the Dockerfile). The first build takes a while (Boost, OpenSSL,
the daemon); later builds reuse the layers and a ccache volume.

### amd64 and arm64

```
docker buildx build --platform linux/amd64,linux/arm64 -f utils/docker/Dockerfile -t pdc-node .
```

Nothing in the Dockerfile is architecture specific. Building the foreign architecture on one machine goes through QEMU
and is very slow for a C++ project of this size; for releases build each architecture on a native runner and merge the
manifests (`docker buildx imagetools create`).

## Running a node

```
docker compose -f utils/docker/compose.yml up -d --build
```

- P2P `19121` is published; the daemon RPC `19211` is published on `127.0.0.1` only. **pdcd's RPC has no authentication,
  no TLS and exposes node-control calls (`start_mining`, `set_maintainers_info.bin`, ...). Never publish it directly.**
- Chain data lives in the `pdc-data` volume. To add seed nodes without rebuilding, put a `seed_nodes.txt` in it
  (format: `utils/seed_nodes.txt.example`).

## Serving wallets: the public-node gateway

Wallets that use a remote node (the desktop wallet, or a browser wallet that cannot open raw TCP) need an RPC endpoint
they can reach. `gateway/` is an nginx front end that makes it safe to offer one:

- only the calls a wallet needs are forwarded: `/getinfo`, `/getheight`, `/gettransactions`, `/sendrawtransaction`,
  `/getblocks.bin`, `/get_o_indexes.bin`, `/getrandom_outs3.bin`, `/get_tx_pool.bin`, `/check_keyimages.bin`, and a
  list of read-only `/json_rpc` methods (`gateway/gateway.js`);
- everything that controls the node or sends it a secret key is refused: mining, `submitblock*`, `getblocktemplate`,
  `reset_transaction_pool`, `remove_tx_from_pool`, `set_maintainers_info.bin`, `decrypt_tx_details` (takes a tx secret
  key), `find_outs_in_recent_blocks` (takes a view key), the legacy random-output calls;
- ambiguous JSON-RPC bodies (repeated or escaped `method` key, batches) are rejected rather than guessed at;
- CORS and `OPTIONS` preflight so browser wallets work (`CORS_ALLOW_ORIGIN`, default `*`);
- per-client rate limits (`RATE_LIGHT`, `RATE_HEAVY`) and no client addresses are logged or passed to the daemon.

```
docker compose -f utils/docker/compose.yml --profile gateway up -d --build      # http://127.0.0.1:8080
NODE_DOMAIN=node.example.org docker compose -f utils/docker/compose.yml --profile tls up -d --build   # https://node.example.org
```

The gateway speaks plain HTTP and is bound to `127.0.0.1`. Publish it only through the `tls` profile (Caddy, automatic
HTTPS) or your own TLS proxy: the gateway trusts `X-Forwarded-For` from private networks to rate limit per client, so
exposing it directly to the internet would let clients spoof that header.

The wallet's own node client is HTTP only, so TLS always terminates at this proxy.

### Testing the gateway

```
utils/docker/gateway/test/run.sh
```

Starts a mock daemon and the gateway in Docker and checks the allowlist, binary integrity, CORS, privacy headers and
rate limiting end to end (needs `docker` and `curl`).

### End-to-end test of the wallet on a real chain

```
utils/docker/e2e/run.sh
```

Starts a testnet node (offline, clock accelerated 60x so blocks take a couple of seconds), the gateway, and a runner that drives
the real wallet engine through the Flutter wallet's Dart code: mine to a wallet, deploy an asset, send it, emit, burn, add it
in a second wallet, and check the node's view after each step. The first run builds everything (tens of minutes); it needs
about 20 GB of Docker disk.
