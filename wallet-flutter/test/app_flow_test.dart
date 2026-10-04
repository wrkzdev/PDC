import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/app/wallet_controller.dart';
import 'package:pdc_wallet/main.dart';
import 'package:pdc_wallet/wallet/mock_wallet_core.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

Future<void> _bigScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('create a wallet, deploy an asset, then see it and send it', (tester) async {
    await _bigScreen(tester);
    final controller = WalletController(MockWalletCore(), isDemoEngine: true);
    await tester.pumpWidget(PdcWalletApp(controller: controller));

    // demo banner is always visible with the demo engine
    expect(find.textContaining('Demo engine'), findsOneWidget);

    // create wallet; short passwords are refused
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'short');
    await tester.enterText(find.widgetWithText(TextField, 'Repeat password'), 'short');
    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8 characters'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
    await tester.enterText(find.widgetWithText(TextField, 'Repeat password'), 'correct horse');
    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    // recovery phrase must be acknowledged before continuing
    expect(find.text('Write down your recovery phrase'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // home: native balance is shown
    expect(find.textContaining('100 PDC'), findsOneWidget);

    // assets tab -> deploy
    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('do not hold any assets'), findsOneWidget);
    await tester.tap(find.text('Deploy asset'));
    await tester.pumpAndSettle();

    // invalid ticker is explained, nothing is deployed
    await tester.enterText(find.widgetWithText(TextField, 'Ticker'), 'BAD TICKER');
    await tester.enterText(find.widgetWithText(TextField, 'Maximum supply'), '1000');
    await tester.tap(find.textContaining('Deploy (fee'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ticker must be 1-14 letters or digits'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Ticker'), 'GOLD');
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Gold Token');
    await tester.enterText(find.widgetWithText(TextField, 'Initial supply'), '10');
    await tester.tap(find.textContaining('Deploy (fee'));
    await tester.pumpAndSettle();
    expect(find.text('Deploy this asset?'), findsOneWidget);
    expect(find.textContaining('cannot be changed afterwards'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
    await tester.pumpAndSettle();
    expect(find.text('Asset submitted'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    // asset is listed with its supply; fee was taken from the native balance
    expect(find.textContaining('10 GOLD'), findsOneWidget);
    expect(controller.nativeBalance!.unlocked.format(), '99.99');

    // send some of the new asset
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<AssetId>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('GOLD  (10').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Recipient address'), 'PxSOMEONE');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '2.5');
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm payment'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent. Transaction'), findsOneWidget);
    final gold = controller.balances.firstWhere((b) => b.ticker == 'GOLD');
    expect(gold.formatUnlocked(), '7.5');
  });

  testWidgets('plain http to a remote host is allowed, with a visible warning', (tester) async {
    await _bigScreen(tester);
    final controller = WalletController(MockWalletCore(), isDemoEngine: true);
    await tester.pumpWidget(PdcWalletApp(controller: controller));
    await tester.enterText(find.widgetWithText(TextField, 'Node address'), 'http://node.example.org:19211');
    await tester.pump();
    expect(find.textContaining('not encrypted'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse');
    await tester.enterText(find.widgetWithText(TextField, 'Repeat password'), 'correct horse');
    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();
    // the recovery phrase dialog appears: the wallet was created against the http node
    expect(find.text('Write down your recovery phrase'), findsOneWidget);
    expect(controller.node.url, 'http://node.example.org:19211');
  });

  testWidgets('no warning for loopback or for https on the demo engine', (tester) async {
    await _bigScreen(tester);
    final controller = WalletController(MockWalletCore(), isDemoEngine: true);
    await tester.pumpWidget(PdcWalletApp(controller: controller));
    await tester.enterText(find.widgetWithText(TextField, 'Node address'), 'http://127.0.0.1:19211');
    await tester.pump();
    expect(find.textContaining('not encrypted'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Node address'), 'https://node.example.org');
    await tester.pump();
    expect(find.textContaining('not encrypted'), findsNothing);
    expect(find.textContaining('does not encrypt'), findsNothing);
  });

  testWidgets('https with the real engine says the engine does not encrypt yet', (tester) async {
    await _bigScreen(tester);
    final controller = WalletController(MockWalletCore(), isDemoEngine: false);
    await tester.pumpWidget(PdcWalletApp(controller: controller));
    await tester.enterText(find.widgetWithText(TextField, 'Node address'), 'https://node.example.org');
    await tester.pump();
    expect(find.textContaining('does not encrypt the node connection'), findsOneWidget);
  });
}
