import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/app/app_settings.dart';
import 'package:pdc_wallet/app/wallet_controller.dart';
import 'package:pdc_wallet/main.dart';
import 'package:pdc_wallet/wallet/mock_wallet_core.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('node, wallet name and theme survive a restart; the password and phrase are never stored', () async {
    final first = WalletController(MockWalletCore(), isDemoEngine: true, settings: await AppSettings.load());
    first.node = NodeEndpoint('https://node.example.org');
    await first.createWallet('savings', 'hunter2hunter2');
    await first.setNode(NodeEndpoint('https://other.example.org:19211'));
    await first.setThemeMode(ThemeMode.dark);

    final second = WalletController(MockWalletCore(), isDemoEngine: true, settings: await AppSettings.load());
    expect(second.node.url, 'https://other.example.org:19211');
    expect(second.lastWalletName, 'savings');
    expect(second.themeMode, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect(prefs.get(k).toString(), isNot(contains('hunter2')));
      expect(prefs.get(k).toString(), isNot(contains('mock1')));
    }
  });

  test('a saved plain-http remote node is ignored instead of trusted', () async {
    SharedPreferences.setMockInitialValues({'node_url': 'http://node.example.org:19211'});
    final c = WalletController(MockWalletCore(), isDemoEngine: true, settings: await AppSettings.load());
    expect(c.node.url, 'http://127.0.0.1:19211');
  });

  test('garbage in storage falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({'node_url': 'not a url', 'theme_mode': 'neon'});
    final c = WalletController(MockWalletCore(), isDemoEngine: true, settings: await AppSettings.load());
    expect(c.node.url, 'http://127.0.0.1:19211');
    expect(c.themeMode, ThemeMode.system);
  });

  testWidgets('the welcome screen opens on Open with the last wallet name once one exists', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'last_wallet_name': 'savings'});
    final c = WalletController(MockWalletCore(), isDemoEngine: true, settings: await AppSettings.load());
    await tester.pumpWidget(PdcWalletApp(controller: c));
    expect(find.text('Open wallet'), findsOneWidget);
    expect(find.text('Repeat password'), findsNothing);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Wallet name')).controller!.text, 'savings');
  });
}
