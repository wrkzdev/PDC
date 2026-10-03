// ignore_for_file: avoid_relative_lib_imports
// Drives the REAL pdc_wallet_core library through the wallet's own Dart code (NativeRawWalletApi + InvokeWalletCore),
// offline: the node address points nowhere, so only what a wallet can do without a chain is checked. Run by the Docker
// walletlib-dart-check stage; PDC_WALLET_CORE_LIB points at the library.
//
// Pure Dart (no Flutter): the wallet code it imports has no Flutter dependencies.

import 'dart:io';

import '../../../lib/core/amount.dart';
import '../../../lib/core/asset_rules.dart';
import '../../../lib/wallet/invoke_wallet_core.dart';
import '../../../lib/wallet/native/native_raw_wallet_api.dart';
import '../../../lib/wallet/wallet_core.dart';

int failures = 0;

void check(String name, bool ok, [Object? detail]) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $name${detail == null ? '' : ': $detail'}');
  if (!ok) failures++;
}

Future<String?> errorOf(Future<void> Function() f) async {
  try {
    await f();
    return null;
  } on WalletException catch (e) {
    return e.message;
  }
}

Future<void> main() async {
  final lib = findWalletCoreLibrary();
  if (lib == null) {
    stderr.writeln('PDC_WALLET_CORE_LIB is not set or points nowhere');
    exit(2);
  }
  final work = Directory.systemTemp.createTempSync('pdc_real_').path;
  final api = NativeRawWalletApi(lib);
  check('library loads and reports its version', api.engineVersion.startsWith('2.'), api.engineVersion);

  final core = InvokeWalletCore(api, workingDir: work);
  await core.connect(NodeEndpoint('http://127.0.0.1:1')); // nothing listens there: everything below is offline
  check('connect answers', true);

  // create
  final phrase = await core.createWallet(name: 'one.wallet', password: 'correct-horse-1');
  final words = phrase.trim().split(RegExp(r'\s+')).length;
  check('recovery phrase has 24-26 words', words >= 24 && words <= 26, '$words words');
  final address = await core.address();
  check('address is a Px address', address.startsWith('Px') && address.length > 90, address.substring(0, 10));
  final balances = await core.balances();
  check('native balance is listed and zero', balances.length == 1 && balances.single.assetId.isNative && balances.single.total.isZero);
  check('native entry is PDC with 12 decimals', balances.single.ticker == 'PDC' && balances.single.decimalPoint == 12);
  check('history is empty', (await core.history()).isEmpty);
  check('sync progress is a fraction', (await core.syncProgress()) >= 0);

  // lock and reopen
  await core.closeWallet();
  check('calls after close are refused', await errorOf(() => core.balances().then((_) {})) != null);
  final wrong = await errorOf(() => core.openWallet(name: 'one.wallet', password: 'not-the-password'));
  check('wrong password is refused', wrong != null, wrong);
  await core.openWallet(name: 'one.wallet', password: 'correct-horse-1');
  check('reopened wallet has the same address', await core.address() == address);
  await core.closeWallet();

  // restore from the recovery phrase must reproduce the same address
  await core.restoreWallet(name: 'two.wallet', password: 'another-password-2', seedPhrase: phrase);
  check('restore from phrase gives the same address', await core.address() == address);
  final bad = await errorOf(() => core.restoreWallet(
      name: 'three.wallet', password: 'another-password-3', seedPhrase: 'not a valid recovery phrase at all'));
  check('an invalid phrase is refused', bad != null, bad);
  // wallet two is still open from the restore; opening an open wallet again is refused by the engine
  final again = await errorOf(() => core.openWallet(name: 'two.wallet', password: 'another-password-2'));
  check('opening an already open wallet is refused', again != null, again);

  // spending without funds must fail cleanly, not crash
  final send = await errorOf(() => core.send(toAddress: address, amount: Amount.parse('1')).then((_) {}));
  check('sending without funds is an error', send != null, send);
  final deploy = await errorOf(() => core
      .deployAsset(AssetDraft(
        ticker: 'GOLD',
        fullName: 'Gold',
        decimalPoint: 12,
        totalMaxSupply: AssetRules.parseSupply('1000', 12),
        initialSupply: AssetRules.parseSupply('10', 12),
      ))
      .then((_) {}));
  check('deploying an asset without funds is an error', deploy != null, deploy);
  final burn = await errorOf(() => core.burnAsset(asset: const AssetId('a5000000000000000000000000000000000000000000000000000000000000ff'), amount: Amount.parse('1', decimals: 2)).then((_) {}));
  check('burning an unknown asset is an error', burn != null, burn);

  await core.closeWallet();
  stdout.writeln(failures == 0 ? 'REAL ENGINE CHECK PASSED' : 'REAL ENGINE CHECK FAILED ($failures)');
  exit(failures == 0 ? 0 : 1);
}
