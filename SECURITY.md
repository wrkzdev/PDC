# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting on this
repository (Security tab, "Report a vulnerability"). Include the affected version (`pdcd --version`), what an attacker
can do, and steps or a test case to reproduce it.

Problems that can split the network or change consensus (block or transaction validation, difficulty, PoW/PoS rules,
hard-fork gating) are the most serious: report them privately first, and expect the fix to be coordinated with node
operators and miners before it is public.

## Network authority keys

Four public keys are compiled into every node and wallet. Whoever holds the matching private key can act with the
authority listed below, so how they are stored matters as much as the code.

| Constant (`src/currency_core/currency_config.h`) | What the private key can do | Holder / backup |
|---|---|---|
| `P2P_MAINTAINERS_PUB_KEY` (mainnet) | sign network-wide maintainer messages: alerts and the `set_maintainers_info` command that nodes obey | _maintainers: fill in_ |
| `P2P_MAINTAINERS_PUB_KEY` (testnet) | same, for testnet | _maintainers: fill in_ |
| `ALIAS_SHORT_NAMES_VALIDATION_PUB_KEY` | authorize registration of aliases shorter than 6 characters | _maintainers: fill in_ |
| `WALLET_ASSETS_WHITELIST_VALIDATION_PUBLIC_KEY` | sign the asset whitelist wallets download from `api.privacydatacoin.com` | _maintainers: fill in_ |

The public halves are listed in `utils/pdc_authority_pubkeys.txt`. The private halves must never be committed
(`*.SECRET*` is git-ignored); keep at least one offline, encrypted backup held by someone other than the day-to-day
operator.

Rotating a key means releasing new binaries, because the public key is compiled in; plan for that before a key is
ever lost or exposed. Changing `P2P_MAINTAINERS_PUB_KEY`, the alias key or any consensus constant is a coordinated
network upgrade, not a routine change.

## Running a public node

The daemon RPC has no authentication or TLS and exposes node-control calls. Never publish port 19211. To serve wallets,
use the gateway in `utils/docker/gateway`, which exposes only wallet-safe calls, and see `utils/docker/README.md`.
