@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/core/json_exact.dart';
import 'package:pdc_wallet/wallet/invoke_wallet_core.dart';
import 'package:pdc_wallet/wallet/native/native_raw_wallet_api.dart';
import 'package:pdc_wallet/wallet/native/pdc_wallet_bindings.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

/// Builds native_stub/pdc_wallet_core_stub.c into a shared library with the C compiler on PATH.
/// Returns null when there is no compiler, in which case these tests are skipped. Synchronous because `skip:` is
/// evaluated while the tests are registered, before any setUpAll runs.
String? buildStub(Directory dir, String name, {List<String> extra = const []}) {
  final ext = Platform.isWindows ? 'dll' : (Platform.isMacOS ? 'dylib' : 'so');
  final out = '${dir.path}${Platform.pathSeparator}$name.$ext';
  for (final cc in ['gcc', 'cc', 'clang']) {
    try {
      final r = Process.runSync(cc, ['-shared', '-fPIC', '-O1', ...extra, '-o', out, 'native_stub/pdc_wallet_core_stub.c']);
      if (r.exitCode == 0 && File(out).existsSync()) return out;
    } on ProcessException {
      continue;
    }
  }
  return null;
}

void main() {
  final tmp = Directory.systemTemp.createTempSync('pdc_stub_');
  final String? stub = buildStub(tmp, 'pdc_wallet_core_stub');
  final skipReason = stub == null ? 'no C compiler available to build the stub library' : null;

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // the loaded library may still be locked on Windows; the OS temp cleaner will remove it
    }
  });

  group('PdcWalletBindings', () {
    test('calls every function and releases results', () {
      final b = PdcWalletBindings(DynamicLibrary.open(stub!));
      expect(b.version(), 'stub-1.0');
      expect(b.shutdown(), contains('OK'));
      expect(b.init('https://node.example.org:19211', 'wd', 0), contains('"return_code":"OK"'));
      expect(b.init('fail', 'wd', 0), contains('BAD_ARG'));
      expect(b.close(5), 'closed 5');
      expect(b.status(1), contains('current_daemon_height'));
      expect(b.open('w', 'right'), contains('"wallet_id":9'));
      expect(b.open('w', 'wrong'), contains('WRONG_PASSWORD'));
      expect(b.generate('mywallet', 'pw'), contains('"name":"mywallet"'));
    }, skip: skipReason);

    test('non-ASCII text survives the trip as UTF-8', () {
      final b = PdcWalletBindings(DynamicLibrary.open(stub!));
      const seed = 'héllo wörld ✓ 日本語 😀';
      final reply = decodeJsonExact(b.restore(seed, 'p', 'pw', '')) as Map;
      expect(reply['a'], seed);
    }, skip: skipReason);

    test('a 1 MB request is passed whole and the pointer is freed', () {
      final b = PdcWalletBindings(DynamicLibrary.open(stub!));
      final big = '{"jsonrpc":"2.0","id":1,"method":"x","params":{"d":"${'a' * (1024 * 1024)}"}}';
      final reply = decodeJsonExact(b.invoke(3, big)) as Map;
      expect(reply['wallet'], 3);
      expect(reply['len'], utf8.encode(big).length);
      // many calls in a row: would exhaust memory quickly if results were not released
      for (var i = 0; i < 2000; i++) {
        b.invoke(i, '{"id":$i}');
      }
    }, skip: skipReason);

    test('refuses a library with a different ABI version', () async {
      final bad = buildStub(tmp, 'pdc_wallet_core_bad', extra: ['-DSTUB_ABI_VERSION=999']);
      expect(bad, isNotNull);
      expect(() => PdcWalletBindings(DynamicLibrary.open(bad!)), throwsA(isA<WalletCoreLibraryException>()));
    }, skip: skipReason);
  });

  group('NativeRawWalletApi + InvokeWalletCore over the real FFI path', () {
    test('create, open, close and error replies work through isolates', () async {
      final api = NativeRawWalletApi(stub!);
      expect(api.engineVersion, 'stub-1.0');
      final core = InvokeWalletCore(api, workingDir: '${tmp.path}${Platform.pathSeparator}wd');
      await core.connect(NodeEndpoint('https://node.example.org:19211'));
      expect(await core.createWallet(name: 'w', password: 'pw'), 'word1 word2');
      await core.closeWallet();
      await core.openWallet(name: 'w', password: 'right');
      await expectLater(core.openWallet(name: 'w', password: 'wrong'),
          throwsA(isA<WalletException>().having((e) => e.message, 'message', 'WRONG_PASSWORD')));
      expect(await api.init('fail', 'wd', 0), contains('BAD_ARG'));
    }, skip: skipReason);

    test('concurrent calls do not interfere', () async {
      final api = NativeRawWalletApi(stub!);
      final replies = await Future.wait([for (var i = 0; i < 8; i++) api.invoke(i, '{"id":$i}')]);
      for (var i = 0; i < 8; i++) {
        final m = decodeJsonExact(replies[i]) as Map;
        expect(m['wallet'], i);
        expect((m['request'] as Map)['id'], i);
      }
    }, skip: skipReason);
  });

  group('findWalletCoreLibrary', () {
    test('honours PDC_WALLET_CORE_LIB only when the file exists', () {
      final f = File('${tmp.path}${Platform.pathSeparator}custom.lib')..writeAsStringSync('x');
      expect(findWalletCoreLibrary(environment: {'PDC_WALLET_CORE_LIB': f.path}), f.path);
      expect(findWalletCoreLibrary(environment: {'PDC_WALLET_CORE_LIB': '${f.path}.missing'}), isNull);
    });

    test('looks next to the executable', () {
      final name = Platform.isWindows ? 'pdc_wallet_core.dll' : (Platform.isMacOS ? 'libpdc_wallet_core.dylib' : 'libpdc_wallet_core.so');
      final dir = Directory('${tmp.path}${Platform.pathSeparator}app')..createSync();
      final exe = '${dir.path}${Platform.pathSeparator}pdc_wallet${Platform.isWindows ? '.exe' : ''}';
      expect(findWalletCoreLibrary(environment: const {}, executablePath: exe), isNull);
      File('${dir.path}${Platform.pathSeparator}$name').writeAsStringSync('x');
      expect(findWalletCoreLibrary(environment: const {}, executablePath: exe), '${dir.path}${Platform.pathSeparator}$name');
    });
  });
}
