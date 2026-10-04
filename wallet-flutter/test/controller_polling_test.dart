import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/app/wallet_controller.dart';
import 'package:pdc_wallet/ui/common.dart';
import 'package:pdc_wallet/wallet/mock_wallet_core.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

class _ScriptedCore extends MockWalletCore {
  double progress = 0.5;
  Object? failWith;
  int reads = 0;

  @override
  Future<double> syncProgress() async {
    reads++;
    if (failWith != null) throw failWith!;
    return progress;
  }
}

void main() {
  const every = Duration(seconds: 5);

  testWidgets('polling picks up sync progress without any user action and stops on lock', (tester) async {
    final core = _ScriptedCore();
    final c = WalletController(core, isDemoEngine: true, pollInterval: every);
    await c.createWallet('w', 'password1');
    expect(c.syncProgress, 0.5);
    expect(c.isSynced, isFalse);

    var notified = 0;
    c.addListener(() => notified++);

    core.progress = 1;
    await tester.pump(every);
    expect(c.syncProgress, 1);
    expect(c.isSynced, isTrue);
    expect(notified, 1);

    // nothing changed: the next read must not repaint the UI
    await tester.pump(every);
    expect(notified, 1);

    await c.lock();
    final readsAtLock = core.reads;
    await tester.pump(every * 3);
    expect(core.reads, readsAtLock, reason: 'no reads after the wallet is locked');
    expect(c.balances, isEmpty);
  });

  testWidgets('a failed background read keeps the last data and reports the error, then clears it', (tester) async {
    final core = _ScriptedCore();
    final c = WalletController(core, isDemoEngine: true, pollInterval: every);
    await c.createWallet('w', 'password1');
    final before = c.balances;

    core.failWith = WalletException('node unreachable');
    await tester.pump(every);
    expect(c.refreshError, contains('node unreachable'));
    expect(c.balances, before);

    core.failWith = null;
    await tester.pump(every);
    expect(c.refreshError, isNull);
    await c.lock();
  });

  testWidgets('polling pauses while the app is in the background', (tester) async {
    final core = _ScriptedCore();
    final c = WalletController(core, isDemoEngine: true, pollInterval: every);
    await c.createWallet('w', 'password1');
    final reads = core.reads;

    c.setForeground(false);
    await tester.pump(every * 3);
    expect(core.reads, reads);

    core.progress = 0.75;
    c.setForeground(true);
    await tester.pump();
    expect(c.syncProgress, 0.75);
    await c.lock();
  });

  test('sync percent is cut, never rounded up to 100', () {
    expect(formatSyncPercent(0.9996), '99.9');
    expect(formatSyncPercent(1), '100');
    expect(formatSyncPercent(0), '0.0');
    expect(formatSyncPercent(0.5), '50.0');
    expect(formatSyncPercent(double.nan), '0.0');
  });
}
