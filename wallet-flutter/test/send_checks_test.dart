import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/app/wallet_controller.dart';
import 'package:pdc_wallet/main.dart';
import 'package:pdc_wallet/wallet/mock_wallet_core.dart';

Future<WalletController> _openWallet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = WalletController(MockWalletCore(), isDemoEngine: true);
  await c.createWallet('w', 'password1');
  await tester.pumpWidget(PdcWalletApp(controller: c));
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('Max leaves the network fee behind', (tester) async {
    await _openWallet(tester);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Amount')).controller!.text, '99.99');
  });

  testWidgets('spending everything without leaving the fee is refused before any dialog', (tester) async {
    final c = await _openWallet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Recipient address'), 'PxSOMEONE');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '100');
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('network fee comes on top'), findsOneWidget);
    expect(find.text('Confirm payment'), findsNothing);
    expect(c.nativeBalance!.unlocked.format(), '100');
  });
}
