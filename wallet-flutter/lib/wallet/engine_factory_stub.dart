import 'engine_choice.dart';
import 'mock_wallet_core.dart';

EngineChoice createEngine(String requested) {
  if (requested != 'demo') {
    throw StateError(
      'PDC_ENGINE=$requested is not available on this platform yet; use the demo engine',
    );
  }
  return EngineChoice(
    core: MockWalletCore(),
    isDemo: true,
    description: 'demo engine',
  );
}
