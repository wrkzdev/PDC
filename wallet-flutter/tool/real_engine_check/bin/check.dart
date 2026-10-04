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
  } on FormatException catch (e) {
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

  // restore from the secret keys must give the address of the same wallet restored from its phrase. The vector is the
  // 25-word test phrase of tests/unit_tests/wallet_seed_test.cpp with its spend and view keys.
  await core.closeWallet();
  final vectorPhrase = '${List.filled(24, 'dew').join(' ')} god';
  const vectorSpend = '5e051454d7226b5734ebd64f754b57db4c655ecda00bd324f1b241d0b6381c0f';
  const vectorView = '7dde5590fdf430568c00556ac2accf09da6cde9a29a4bc7d1cb6fd267130f006';
  await core.restoreWallet(name: 'vector-phrase.wallet', password: 'vector-pass-1', seedPhrase: vectorPhrase);
  final vectorAddress = await core.address();
  await core.closeWallet();
  await core.restoreWalletFromKeys(name: 'vector-keys.wallet', password: 'vector-pass-2', spendKey: vectorSpend, viewKey: vectorView);
  check('restore from keys gives the address of the same phrase', await core.address() == vectorAddress, vectorAddress.substring(0, 10));
  check('a wallet restored from keys is not watch-only: its status answers', (await core.syncProgress()) >= 0);
  await core.closeWallet();
  await core.openWallet(name: 'vector-keys.wallet', password: 'vector-pass-2');
  check('a wallet restored from keys reopens with the same address', await core.address() == vectorAddress);
  await core.closeWallet();
  // a spend key with the view key of another wallet is refused, and no wallet file is left behind
  final mismatch = await errorOf(() => core.restoreWalletFromKeys(
      name: 'vector-bad.wallet',
      password: 'vector-pass-3',
      spendKey: vectorSpend,
      viewKey: '8454372096986c457f4e7dceef2f39b6050c35d87b31d9c9eb8d37bf8f1f430f'));
  check('keys that do not belong together are refused', mismatch != null && mismatch.contains('WRONG_SEED'), mismatch);
  check('no wallet file is created for refused keys', !File('$work/wallets/vector-bad.wallet').existsSync());
  final shortKey = await errorOf(() => core.restoreWalletFromKeys(name: 'vector-bad2.wallet', password: 'vector-pass-4', spendKey: 'abc', viewKey: vectorView));
  check('a malformed key is refused before the engine is called', shortKey != null, shortKey);

  await core.closeWallet();
  await api.shutdown(); // the engine must be stopped before exit, or the process can hang on Windows
  stdout.writeln(failures == 0 ? 'REAL ENGINE CHECK PASSED' : 'REAL ENGINE CHECK FAILED ($failures)');
  exit(failures == 0 ? 0 : 1);
}
