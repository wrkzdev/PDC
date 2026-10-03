// dart:ffi binding of the pdc_wallet_core C ABI (src/wallet_core_lib/pdc_wallet_core.h). Synchronous and blocking: callers run
// it off the UI isolate (see NativeRawWalletApi). Every string the library returns is copied and released with
// pdc_wallet_free().

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// ABI version this binding was written for; must equal PDC_WALLET_CORE_ABI_VERSION in pdc_wallet_core.h.
const int expectedWalletCoreAbiVersion = 1;

class WalletCoreLibraryException implements Exception {
  WalletCoreLibraryException(this.message);
  final String message;
  @override
  String toString() => 'WalletCoreLibraryException: $message';
}

typedef _Str0N = Pointer<Utf8> Function();
typedef _Str0D = Pointer<Utf8> Function();
typedef _Str3N = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _Str3D = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Str2N = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Str2D = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Str4N = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Str4D = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _IdN = Pointer<Utf8> Function(Int64);
typedef _IdD = Pointer<Utf8> Function(int);
typedef _IdStrN = Pointer<Utf8> Function(Int64, Pointer<Utf8>);
typedef _IdStrD = Pointer<Utf8> Function(int, Pointer<Utf8>);
typedef _FreeN = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);

class PdcWalletBindings {
  PdcWalletBindings(DynamicLibrary lib)
      : _version = lib.lookupFunction<_Str0N, _Str0D>('pdc_wallet_version'),
        _init = lib.lookupFunction<_Str3N, _Str3D>('pdc_wallet_init'),
        _generate = lib.lookupFunction<_Str2N, _Str2D>('pdc_wallet_generate'),
        _restore = lib.lookupFunction<_Str4N, _Str4D>('pdc_wallet_restore'),
        _open = lib.lookupFunction<_Str2N, _Str2D>('pdc_wallet_open'),
        _close = lib.lookupFunction<_IdN, _IdD>('pdc_wallet_close'),
        _status = lib.lookupFunction<_IdN, _IdD>('pdc_wallet_status'),
        _invoke = lib.lookupFunction<_IdStrN, _IdStrD>('pdc_wallet_invoke'),
        _free = lib.lookupFunction<_FreeN, _FreeD>('pdc_wallet_free') {
    final abi = lib.lookupFunction<Int32 Function(), int Function()>('pdc_wallet_abi_version')();
    if (abi != expectedWalletCoreAbiVersion) {
      throw WalletCoreLibraryException(
          'wallet library has ABI version $abi, this app needs $expectedWalletCoreAbiVersion; rebuild or update it');
    }
  }

  final _Str0D _version;
  final _Str3D _init;
  final _Str2D _generate;
  final _Str4D _restore;
  final _Str2D _open;
  final _IdD _close;
  final _IdD _status;
  final _IdStrD _invoke;
  final _FreeD _free;

  String _take(Pointer<Utf8> p) {
    if (p == nullptr) throw WalletCoreLibraryException('wallet library returned NULL');
    try {
      return p.toDartString();
    } finally {
      _free(p);
    }
  }

  String version() => _take(_version());

  String init(String nodeAddress, String workingDir, int logLevel) => using((a) =>
      _take(_init(nodeAddress.toNativeUtf8(allocator: a), workingDir.toNativeUtf8(allocator: a), logLevel)));

  String generate(String path, String password) =>
      using((a) => _take(_generate(path.toNativeUtf8(allocator: a), password.toNativeUtf8(allocator: a))));

  String restore(String seed, String path, String password, String seedPassword) => using((a) => _take(_restore(
      seed.toNativeUtf8(allocator: a),
      path.toNativeUtf8(allocator: a),
      password.toNativeUtf8(allocator: a),
      seedPassword.toNativeUtf8(allocator: a))));

  String open(String path, String password) =>
      using((a) => _take(_open(path.toNativeUtf8(allocator: a), password.toNativeUtf8(allocator: a))));

  String close(int walletId) => _take(_close(walletId));

  String status(int walletId) => _take(_status(walletId));

  String invoke(int walletId, String jsonRpcRequest) =>
      using((a) => _take(_invoke(walletId, jsonRpcRequest.toNativeUtf8(allocator: a))));
}
