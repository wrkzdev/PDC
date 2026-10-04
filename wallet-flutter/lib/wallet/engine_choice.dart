import 'wallet_core.dart';

/// The wallet engine the app runs on, and whether it is the fake in-memory demo.
class EngineChoice {
  const EngineChoice({
    required this.core,
    required this.isDemo,
    required this.description,
  });

  final WalletCore core;
  final bool isDemo;
  final String description;
}

/// What `--dart-define=PDC_ENGINE=...` selects. Demo is the default until the native engine has been verified on a
/// live testnet.
const String requestedEngine = String.fromEnvironment(
  'PDC_ENGINE',
  defaultValue: 'demo',
);

/// Whether the wallet engine encrypts its connection to the node when the address is https://. It does not yet: the
/// engine's node client (epee http_simple_client) is plain HTTP and ignores the scheme, so TLS is only available by
/// running the node behind a local TLS-terminating proxy. The UI says so instead of implying https:// is protected.
/// Set to true when the engine gains TLS (use https_simple_client in default_http_core_proxy).
const bool engineSupportsTls = false;
