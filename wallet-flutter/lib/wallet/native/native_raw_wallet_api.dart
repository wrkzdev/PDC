// RawWalletApi over the native library. The C calls block (opening a wallet, building a transaction with its proofs
// takes seconds), so each one runs in its own short-lived isolate; the library itself is a process-wide singleton, so
// every isolate talks to the same wallet engine.

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../raw_wallet_api.dart';
import 'pdc_wallet_bindings.dart';

class NativeRawWalletApi implements RawWalletApi {
  /// Loads the library once to fail fast (missing file, wrong ABI) before the app relies on it.
  NativeRawWalletApi(this.libraryPath) {
    final b = PdcWalletBindings(DynamicLibrary.open(libraryPath));
    engineVersion = b.version();
  }

  final String libraryPath;
  late final String engineVersion;

  Future<String> _run(String Function(PdcWalletBindings b) call) {
    final path = libraryPath;
    return Isolate.run(() => call(PdcWalletBindings(DynamicLibrary.open(path))));
  }

  @override
  Future<String> init(String nodeAddress, String workingDir, int logLevel) {
    Directory(workingDir).createSync(recursive: true);
    return _run((b) => b.init(nodeAddress, workingDir, logLevel));
  }

  @override
  Future<String> generate(String path, String password) => _run((b) => b.generate(path, password));

  @override
  Future<String> restore(String seed, String path, String password, String seedPassword) =>
      _run((b) => b.restore(seed, path, password, seedPassword));

  @override
  Future<String> open(String path, String password) => _run((b) => b.open(path, password));

  @override
  Future<String> closeWallet(int walletId) => _run((b) => b.close(walletId));

  @override
  Future<String> getWalletStatus(int walletId) => _run((b) => b.status(walletId));

  @override
  Future<String> invoke(int walletId, String jsonRpcRequest) => _run((b) => b.invoke(walletId, jsonRpcRequest));

  @override
  Future<String> shutdown() => _run((b) => b.shutdown());
}

/// Where the native library is expected, in order: the PDC_WALLET_CORE_LIB environment variable, then next to the
/// executable (how releases ship it). Returns null when it is not found.
String? findWalletCoreLibrary({Map<String, String>? environment, String? executablePath}) {
  final env = environment ?? Platform.environment;
  final override = env['PDC_WALLET_CORE_LIB'];
  if (override != null && override.isNotEmpty) {
    return File(override).existsSync() ? override : null;
  }
  final name = Platform.isWindows
      ? 'pdc_wallet_core.dll'
      : Platform.isMacOS
          ? 'libpdc_wallet_core.dylib'
          : 'libpdc_wallet_core.so';
  final exeDir = File(executablePath ?? Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  final candidates = [
    '$exeDir$sep$name',
    '$exeDir${sep}lib$sep$name',
    // macOS app bundles keep native libraries in Contents/Frameworks, next to Contents/MacOS
    '$exeDir$sep..${sep}Frameworks$sep$name',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

/// Per-user directory for wallet files. Kept outside the app bundle so updates never touch wallets.
String defaultWalletWorkingDir({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final sep = Platform.pathSeparator;
  if (Platform.isWindows) {
    return '${env['APPDATA'] ?? env['USERPROFILE'] ?? '.'}${sep}PdcWallet';
  }
  if (Platform.isMacOS) {
    return '${env['HOME'] ?? '.'}/Library/Application Support/PdcWallet';
  }
  return '${env['XDG_DATA_HOME'] ?? '${env['HOME'] ?? '.'}/.local/share'}/PdcWallet';
}
