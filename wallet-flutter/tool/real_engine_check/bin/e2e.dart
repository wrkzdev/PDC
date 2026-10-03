// ignore_for_file: avoid_relative_lib_imports
// End to end on a real chain: the Flutter wallet's own Dart code -> the real wallet engine -> the public-node gateway
// -> a real testnet pdcd, mined by this script. Deploys an asset, sends it to a second wallet, emits more, burns some,
// and checks the node's view of the asset after every step. Run by utils/docker/e2e/run.sh.
//
// NODE_RPC      the node's own RPC (used only to start mining: the gateway refuses that, by design)
// GATEWAY_URL   what the wallet engine and the node client talk to
// PDC_WALLET_CORE_LIB  the wallet library

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../lib/core/amount.dart';
import '../../../lib/core/asset_rules.dart';
import '../../../lib/node/node_client.dart';
import '../../../lib/wallet/invoke_wallet_core.dart';
import '../../../lib/wallet/native/native_raw_wallet_api.dart';
import '../../../lib/wallet/wallet_core.dart';

int failures = 0;
final started = DateTime.now();

void log(String m) => stderr.writeln('[${DateTime.now().difference(started).inSeconds.toString().padLeft(4)}s] $m');

void check(String name, bool ok, [Object? detail]) {
  log('${ok ? 'ok  ' : 'FAIL'} $name${detail == null ? '' : ': $detail'}');
  if (!ok) failures++;
}

/// Polls [probe] until it returns non-null, or fails after [timeout].
Future<T> waitFor<T>(String what, Future<T?> Function() probe, {Duration timeout = const Duration(minutes: 6), Duration every = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(end)) {
    try {
      final v = await probe();
      if (v != null) return v;
    } on WalletException catch (e) {
      lastError = e; // e.g. BUSY while the wallet refreshes
    } on NodeException catch (e) {
      lastError = e;
    } on SocketException catch (e) {
      lastError = e;
    } on http.ClientException catch (e) {
      lastError = e;
    }
    await Future<void>.delayed(every);
  }
  throw StateError('timed out waiting for $what${lastError == null ? '' : ' (last error: $lastError)'}');
}

Future<String?> errorOf(Future<void> Function() f) async {
  try {
    await f();
    return null;
  } on WalletException catch (e) {
    return e.message;
  }
}

AssetBalance? balanceOf(List<AssetBalance> all, AssetId id) {
  for (final b in all) {
    if (b.assetId == id) return b;
  }
  return null;
}

Future<void> main() async {
  final nodeRpc = Platform.environment['NODE_RPC'] ?? 'http://node:19111';
  final gateway = Platform.environment['GATEWAY_URL'] ?? 'http://gateway:8080';
  final lib = findWalletCoreLibrary();
  if (lib == null) {
    stderr.writeln('PDC_WALLET_CORE_LIB is not set or points nowhere');
    exit(2);
  }

  final direct = NodeClient(NodeEndpoint(nodeRpc));
  final viaGateway = NodeClient(NodeEndpoint(gateway));
  final web = http.Client();

  // ---- wait for the stack
  await waitFor('the node RPC', () async => (await direct.getInfo()).height >= 0 ? true : null);
  await waitFor('the gateway', () async => (await web.get(Uri.parse('$gateway/healthz'))).statusCode == 200 ? true : null);
  final info0 = await viaGateway.getInfo();
  check('the gateway forwards getinfo', info0.height >= 0, 'height ${info0.height}');

  // ---- the gateway must keep refusing node control, even to a client that asks nicely
  final mining = await web.post(Uri.parse('$gateway/start_mining'), body: '{}');
  check('gateway refuses /start_mining', mining.statusCode == 403, mining.statusCode);

  // ---- wallet A
  final api = NativeRawWalletApi(lib);
  log('engine ${api.engineVersion}');
  final work = Directory.systemTemp.createTempSync('pdc_e2e_').path;
  final core = InvokeWalletCore(api, workingDir: work);
  await core.connect(NodeEndpoint(gateway)); // the wallet engine syncs THROUGH the gateway
  await core.createWallet(name: 'alice.wallet', password: 'alice-password-1');
  final alice = await core.address();
  log('alice $alice');

  // ---- mine to alice (testnet, difficulty adjusts to this machine; the node runs on accelerated time)
  final start = await web.post(Uri.parse('$nodeRpc/start_mining'),
      headers: {'Content-Type': 'application/json'}, body: jsonEncode({'miner_address': alice, 'threads_count': 2}));
  check('node starts mining to alice', start.statusCode == 200 && start.body.contains('OK'), start.body.replaceAll('\n', ' '));

  // Zarcanum (confidential outputs, needed for asset operations) starts after height 100 on testnet, coinbase outputs
  // unlock after 10 blocks, and transfers need a pool of decoy outputs: wait for a comfortable margin.
  const targetHeight = 220;
  final h = await waitFor('the chain to reach height $targetHeight', () async {
    final i = await direct.getInfo();
    if (i.height % 10 == 0) log('node height ${i.height}');
    return i.height >= targetHeight ? i.height : null;
  }, timeout: const Duration(minutes: 12), every: const Duration(seconds: 4));
  check('chain reached the target height', h >= targetHeight, h);

  final funded = await waitFor('alice to see spendable PDC', () async {
    final b = balanceOf(await core.balances(), AssetId.native);
    if (b != null && b.unlocked >= Amount.parse('5')) return b;
    final p = await core.syncProgress();
    log('alice sync ${(p * 100).toStringAsFixed(0)}%, unlocked ${b?.unlocked.format() ?? '?'}');
    return null;
  }, timeout: const Duration(minutes: 10), every: const Duration(seconds: 5));
  check('alice has spendable PDC mined through the gateway', funded.unlocked >= Amount.parse('5'), '${funded.unlocked.format()} PDC');

  // ---- deploy an asset
  final draft = AssetDraft(
    ticker: 'TST',
    fullName: 'Test Token',
    metaInfo: 'end to end test',
    decimalPoint: 4,
    totalMaxSupply: AssetRules.parseSupply('1000000', 4),
    initialSupply: AssetRules.parseSupply('1000', 4),
  );
  // A young chain may not have the 15 decoy outputs every confidential transaction must reference yet; the engine then
  // fails with -4. Retry (visibly) rather than depend on exact timing, but never forever.
  final deployed = await waitFor('the asset deployment to be accepted', () async {
    try {
      return await core.deployAsset(draft);
    } on WalletException catch (e) {
      log('deploy not accepted yet (${e.message}); waiting for more blocks');
      return null;
    }
  }, timeout: const Duration(minutes: 4), every: const Duration(seconds: 8));
  log('deploy tx ${deployed.txId}, asset ${deployed.assetId}');
  check('deploy returns a transaction and an asset id', deployed.txId.length == 64 && deployed.assetId.hex.length == 64);

  final onChain = await waitFor('the node to know the asset', () => viaGateway.getAssetInfo(deployed.assetId), timeout: const Duration(minutes: 5));
  check('node reports the ticker and name', onChain.ticker == 'TST' && onChain.fullName == 'Test Token', '${onChain.ticker} / ${onChain.fullName}');
  check('node reports 4 decimals', onChain.decimalPoint == 4);
  check('node reports the exact maximum supply', onChain.totalMaxSupply == draft.totalMaxSupply, onChain.totalMaxSupply);
  check('node reports the initial supply', onChain.currentSupply == draft.initialSupply, onChain.currentSupply);
  check('node reports a non-zero owner', onChain.owner.isNotEmpty && onChain.owner.replaceAll('0', '').isNotEmpty);

  final asset = deployed.assetId;
  final held = await waitFor('alice to hold the initial supply', () async {
    final b = balanceOf(await core.balances(), asset);
    return (b != null && b.unlocked.atomic == draft.initialSupply) ? b : null;
  }, timeout: const Duration(minutes: 5));
  check('alice holds 1000 TST', held.formatUnlocked() == '1000' && held.ticker == 'TST', held.formatUnlocked());

  final listed = await viaGateway.listAssets(offset: 0, count: 50);
  check('the new asset is in the node\'s asset list', listed.any((a) => a.assetId == asset));

  // ---- a second wallet to receive some
  await core.closeWallet();
  await core.createWallet(name: 'bob.wallet', password: 'bob-password-1');
  final bob = await core.address();
  await core.closeWallet();
  await core.openWallet(name: 'alice.wallet', password: 'alice-password-1');

  // ---- send TST from alice to bob
  final sent = await waitFor('the send to be accepted', () async {
    try {
      return await core.send(toAddress: bob, amount: Amount.parse('25.5', decimals: 4), asset: asset);
    } on WalletException catch (e) {
      log('send not yet possible: ${e.message}');
      return null;
    }
  }, timeout: const Duration(minutes: 5), every: const Duration(seconds: 6));
  log('send tx $sent');
  check('sending an asset returns a transaction id', sent.length == 64);

  final afterSend = await waitFor('alice\'s balance to drop by the amount sent', () async {
    final b = balanceOf(await core.balances(), asset);
    return (b != null && b.total.atomic == draft.initialSupply - BigInt.from(255000) && b.unlocked.atomic == b.total.atomic) ? b : null;
  }, timeout: const Duration(minutes: 5));
  check('alice has 974.5 TST left', afterSend.formatUnlocked() == '974.5', afterSend.formatUnlocked());

  // ---- emit more (owner only)
  final emitTx = await core.emitAsset(asset: asset, amount: Amount.parse('500', decimals: 4));
  log('emit tx $emitTx');
  final afterEmit = await waitFor('the node to show the emission', () async {
    final a = await viaGateway.getAssetInfo(asset);
    return (a != null && a.currentSupply == AssetRules.parseSupply('1500', 4)) ? a : null;
  }, timeout: const Duration(minutes: 5));
  check('node supply is 1500 after emitting 500', afterEmit.currentSupply == AssetRules.parseSupply('1500', 4), afterEmit.currentSupply);

  // ---- burn some
  final burnTx = await core.burnAsset(asset: asset, amount: Amount.parse('100', decimals: 4));
  log('burn tx $burnTx');
  final afterBurn = await waitFor('the node to show the burn', () async {
    final a = await viaGateway.getAssetInfo(asset);
    return (a != null && a.currentSupply == AssetRules.parseSupply('1400', 4)) ? a : null;
  }, timeout: const Duration(minutes: 5));
  check('node supply is 1400 after burning 100', afterBurn.currentSupply == AssetRules.parseSupply('1400', 4), afterBurn.currentSupply);
  check('maximum supply is unchanged', afterBurn.totalMaxSupply == draft.totalMaxSupply);

  // ---- things that must fail
  final tooMuch = await errorOf(() => core.emitAsset(asset: asset, amount: Amount.parse('999999', decimals: 4)).then((_) {}));
  check('emitting beyond the maximum supply is refused', tooMuch != null, tooMuch);
  final duplicate = await errorOf(() => core
      .deployAsset(AssetDraft(
        ticker: 'bad ticker!',
        fullName: 'x',
        decimalPoint: 4,
        totalMaxSupply: BigInt.one,
        initialSupply: BigInt.one,
      ))
      .then((_) {}));
  check('an invalid ticker is refused before the engine is called', duplicate != null, duplicate);

  // ---- bob sees what alice sent, and cannot emit
  await core.closeWallet();
  await core.openWallet(name: 'bob.wallet', password: 'bob-password-1');
  // the engine hides assets that are not whitelisted or owned: bob must add the asset before it is listed
  check('bob does not list the asset before adding it', balanceOf(await core.balances(), asset) == null);
  await core.addCustomAsset(asset);
  final bobHeld = await waitFor('bob to receive the asset', () async {
    final b = balanceOf(await core.balances(), asset);
    return (b != null && b.total.atomic == BigInt.from(255000)) ? b : null;
  }, timeout: const Duration(minutes: 6), every: const Duration(seconds: 5));
  check('bob received 25.5 TST', bobHeld.formatTotal() == '25.5', bobHeld.formatTotal());
  final notOwner = await errorOf(() => core.emitAsset(asset: asset, amount: Amount.parse('1', decimals: 4)).then((_) {}));
  check('a non-owner cannot emit', notOwner != null, notOwner);
  await core.closeWallet();

  await api.shutdown();
  web.close();
  direct.close();
  viaGateway.close();
  log(failures == 0 ? 'E2E PASSED' : 'E2E FAILED ($failures)');
  exit(failures == 0 ? 0 : 1);
}
