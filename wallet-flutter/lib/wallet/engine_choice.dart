import 'wallet_core.dart';

/// The wallet engine the app runs on, and whether it is the fake in-memory demo.
class EngineChoice {
  const EngineChoice({required this.core, required this.isDemo, required this.description});

  final WalletCore core;
  final bool isDemo;
  final String description;
}

/// What `--dart-define=PDC_ENGINE=...` selects. Demo is the default until the native engine has been verified on a
/// live testnet.
const String requestedEngine = String.fromEnvironment('PDC_ENGINE', defaultValue: 'demo');
