import 'engine_choice.dart';
import 'invoke_wallet_core.dart';
import 'mock_wallet_core.dart';
import 'native/native_raw_wallet_api.dart';

EngineChoice createEngine(String requested) {
  switch (requested) {
    case 'demo':
      return EngineChoice(core: MockWalletCore(), isDemo: true, description: 'demo engine');
    case 'native':
      final lib = findWalletCoreLibrary();
      if (lib == null) {
        throw StateError('PDC_ENGINE=native but the wallet library (pdc_wallet_core) was not found next to the app. '
            'Set PDC_WALLET_CORE_LIB to its full path.');
      }
      final api = NativeRawWalletApi(lib);
      return EngineChoice(
        core: InvokeWalletCore(api, workingDir: defaultWalletWorkingDir()),
        isDemo: false,
        description: 'native engine ${api.engineVersion}',
      );
    default:
      throw StateError('Unknown PDC_ENGINE "$requested" (use demo or native)');
  }
}
