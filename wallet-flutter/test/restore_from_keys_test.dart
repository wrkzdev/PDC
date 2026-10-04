import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/app/wallet_controller.dart';
import 'package:pdc_wallet/core/secret_keys.dart';
import 'package:pdc_wallet/main.dart';
import 'package:pdc_wallet/wallet/invoke_wallet_core.dart';
import 'package:pdc_wallet/wallet/mock_wallet_core.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

import 'invoke_wallet_core_test.dart' show FakeRawApi;

// Keys of the 25-word test phrase "dew x24 god" (tests/unit_tests/wallet_seed_test.cpp).
const _spend = '5e051454d7226b5734ebd64f754b57db4c655ecda00bd324f1b241d0b6381c0f';
const _view = '7dde5590fdf430568c00556ac2accf09da6cde9a29a4bc7d1cb6fd267130f006';


class _RejectingCore extends MockWalletCore {
  @override
  Future<void> restoreWallet({
    required String name,
    required String password,
    required String seedPhrase,
    String seedPassword = '',
  }) async => throw WalletException('WRONG_SEED');
}

void main() {
  group('normalizeSecretKey', () {
    test('accepts 64 hex characters, trimmed and lower-cased', () {
      expect(normalizeSecretKey('  ${_spend.toUpperCase()}\n', 'spend key'), _spend);
    });

    test('refuses anything else and names the key', () {
      for (final bad in ['', 'abc', '${_spend}0', _spend.substring(1), '${_spend.substring(0, 63)}g', 'keys:$_spend']) {
        expect(() => normalizeSecretKey(bad, 'view key'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('view key'))));
      }
    });
  });

  test('the engine is asked to restore "keys:<spend>:<view>" and the keys are never logged', () async {
    final api = FakeRawApi();
    api.rpc['getaddress'] = (_) => '{"address":"PxADDRESS"}';
    final core = InvokeWalletCore(api, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
    await core.connect(NodeEndpoint('http://127.0.0.1:19211'));
    await core.restoreWalletFromKeys(name: 'k.wallet', password: 'pw-pw-pw-1', spendKey: _spend.toUpperCase(), viewKey: ' $_view ');
    expect(api.calls.last, 'restore keys:$_spend:$_view|k.wallet|');
    expect(await core.address(), 'PxADDRESS');
  });

  test('malformed keys never reach the engine', () async {
    final api = FakeRawApi();
    final core = InvokeWalletCore(api, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
    await core.connect(NodeEndpoint('http://127.0.0.1:19211'));
    await expectLater(
      core.restoreWalletFromKeys(name: 'k', password: 'pw-pw-pw-1', spendKey: 'nope', viewKey: _view),
      throwsA(isA<FormatException>()),
    );
    expect(api.calls.where((c) => c.startsWith('restore')), isEmpty);
  });

  group('welcome screen', () {
    Future<WalletController> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WalletController(MockWalletCore(), isDemoEngine: true);
      await tester.pumpWidget(PdcWalletApp(controller: c));
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('Restore offers a recovery phrase or secret keys', (tester) async {
      await pump(tester);
      expect(find.widgetWithText(TextField, 'Recovery phrase'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Secret spend key'), findsNothing);
      await tester.tap(find.text('Secret keys'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Recovery phrase'), findsNothing);
      expect(find.widgetWithText(TextField, 'Secret spend key'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Secret view key'), findsOneWidget);
      // the keys are secrets: they are hidden while typed
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Secret spend key')).obscureText, isTrue);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Secret view key')).obscureText, isTrue);
    });

    testWidgets('bad keys are explained and nothing opens', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Secret keys'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Secret spend key'), 'abc');
      await tester.enterText(find.widgetWithText(TextField, 'Secret view key'), _view);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('spend key must be 64 hexadecimal characters'), findsOneWidget);
      expect(c.isOpen, isFalse);
    });

    testWidgets('valid keys open the wallet and remember its name', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Secret keys'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Secret spend key'), _spend);
      await tester.enterText(find.widgetWithText(TextField, 'Secret view key'), _view);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      expect(c.isOpen, isTrue);
      expect(c.lastWalletName, 'my-wallet');
    });
  });

  group('restore from a recovery phrase', () {
    Future<WalletController> pump(WidgetTester tester, WalletCore core) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WalletController(core, isDemoEngine: true);
      await tester.pumpWidget(PdcWalletApp(controller: c));
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('a phrase of the wrong length is explained before the engine is asked', (tester) async {
      final api = FakeRawApi();
      final core = InvokeWalletCore(api, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
      await pump(tester, core);
      await tester.enterText(find.widgetWithText(TextField, 'Recovery phrase'), List.filled(24, 'dew').join(' '));
      await tester.pump();
      expect(find.text('24 words'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('25 or 26 words, but you entered 24'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('restore')), isEmpty);
    });

    testWidgets('a pasted phrase is cleaned up and the seed password is passed on', (tester) async {
      final api = FakeRawApi();
      api.rpc['getaddress'] = (_) => '{"address":"PxADDRESS"}';
      api.rpc['getbalance'] = (_) => '{"balances":[]}';
      api.rpc['get_recent_txs_and_info2'] = (_) => '{"transfers":[]}';
      final core = InvokeWalletCore(api, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
      await pump(tester, core);
      final pasted = '${List.filled(24, 'Dew').join(',\n')}\n  GOD ';
      await tester.enterText(find.widgetWithText(TextField, 'Recovery phrase'), pasted);
      await tester.enterText(find.widgetWithText(TextField, 'Seed password (optional)'), 'my seed pw');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      final restore = api.calls.firstWhere((c) => c.startsWith('restore'));
      expect(restore, 'restore ${List.filled(24, 'dew').join(' ')} god|my-wallet|my seed pw');
    });

    testWidgets('a rejected phrase without a seed password points at show_seed', (tester) async {
      await pump(tester, _RejectingCore());
      await tester.enterText(find.widgetWithText(TextField, 'Recovery phrase'), List.filled(26, 'dew').join(' '));
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('most likely secured with a seed password'), findsOneWidget);
    });

    testWidgets('a rejected phrase with a seed password says the seed password may be wrong', (tester) async {
      await pump(tester, _RejectingCore());
      await tester.enterText(find.widgetWithText(TextField, 'Recovery phrase'), List.filled(26, 'dew').join(' '));
      await tester.enterText(find.widgetWithText(TextField, 'Seed password (optional)'), 'nope');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not accepted with this seed password'), findsOneWidget);
      expect(find.textContaining('most likely secured'), findsNothing);
    });

    testWidgets('the seed password field hides what is typed', (tester) async {
      await pump(tester, MockWalletCore());
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Seed password (optional)')).obscureText, isTrue);
    });
  });
}
