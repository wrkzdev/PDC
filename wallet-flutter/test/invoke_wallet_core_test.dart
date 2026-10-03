import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/core/amount.dart';
import 'package:pdc_wallet/core/asset_rules.dart';
import 'package:pdc_wallet/core/json_exact.dart';
import 'package:pdc_wallet/wallet/invoke_wallet_core.dart';
import 'package:pdc_wallet/wallet/raw_wallet_api.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

/// Answers like plain_wallet_api / the wallet RPC server and records what it was asked.
class FakeRawApi implements RawWalletApi {
  final calls = <String>[];
  final invoked = <Map<String, Object?>>[];
  final Map<String, String Function(Map<String, Object?> params)> rpc = {};
  String initReply = '{"id":0,"jsonrpc":"","result":{"return_code":"OK"}}';
  String generateReply = '{"id":0,"jsonrpc":"2.0","result":{"wallet_id":7,"seed":"one two three","name":"w"}}';
  String openReply = '{"id":0,"jsonrpc":"2.0","result":{"wallet_id":9}}';
  String statusReply = '{"current_wallet_height":50,"current_daemon_height":200,"wallet_state":1}';

  @override
  Future<String> init(String nodeAddress, String workingDir, int logLevel) async {
    calls.add('init $nodeAddress $workingDir');
    return initReply;
  }

  @override
  Future<String> generate(String path, String password) async {
    calls.add('generate $path');
    return generateReply;
  }

  @override
  Future<String> restore(String seed, String path, String password, String seedPassword) async {
    calls.add('restore $seed|$path|$seedPassword');
    return openReply;
  }

  @override
  Future<String> open(String path, String password) async {
    calls.add('open $path');
    return openReply;
  }

  @override
  Future<String> closeWallet(int walletId) async {
    calls.add('close $walletId');
    return 'OK';
  }

  @override
  Future<String> getWalletStatus(int walletId) async => statusReply;

  @override
  Future<String> shutdown() async {
    calls.add('shutdown');
    return '{"response": "OK"}';
  }

  @override
  Future<String> invoke(int walletId, String jsonRpcRequest) async {
    final req = decodeJsonExact(jsonRpcRequest) as Map<String, Object?>;
    invoked.add(req);
    final handler = rpc[req['method']];
    if (handler == null) return '{"id":0,"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}';
    return '{"id":${req['id']},"jsonrpc":"2.0","result":${handler(req['params'] as Map<String, Object?>)}}';
  }
}

void main() {
  late FakeRawApi api;
  late InvokeWalletCore core;

  setUp(() {
    api = FakeRawApi();
    api.rpc['getaddress'] = (_) => '{"address":"PxADDRESS"}';
    core = InvokeWalletCore(api, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
  });

  Future<void> openIt() async {
    await core.connect(NodeEndpoint('https://node.example.org'));
    await core.openWallet(name: 'w', password: 'pw');
  }

  group('lifecycle', () {
    test('connect passes the node url and working dir; engine errors surface', () async {
      await core.connect(NodeEndpoint('https://node.example.org:19211'));
      expect(api.calls.single, 'init https://node.example.org:19211 /data');
      api.initReply = '{"error":{"code":"BAD_ARG"}}';
      expect(core.connect(NodeEndpoint('https://x.example.org')), throwsA(isA<WalletException>()));
      api.initReply = '{"id":0,"jsonrpc":"","result":{"return_code":"BAD_ARG"}}';
      await expectLater(core.connect(NodeEndpoint('https://x.example.org')),
          throwsA(isA<WalletException>().having((e) => e.message, 'message', 'BAD_ARG')));
      api.initReply = 'FAIL';
      expect(core.connect(NodeEndpoint('https://x.example.org')), throwsA(isA<WalletException>()));
      api.initReply = 'OK'; // older engines answer with a bare status word
      await core.connect(NodeEndpoint('https://x.example.org'));
    });

    test('create returns the recovery phrase', () async {
      expect(await core.createWallet(name: 'w', password: 'pw'), 'one two three');
    });

    test('create without a phrase is an error', () async {
      api.generateReply = '{"id":0,"jsonrpc":"2.0","result":{"wallet_id":7}}';
      expect(core.createWallet(name: 'w', password: 'pw'), throwsA(isA<WalletException>()));
    });

    test('a wrong password is reported with the engine code', () async {
      api.openReply = '{"error":{"code":"WRONG_PASSWORD"}}';
      await expectLater(
          core.openWallet(name: 'w', password: 'bad'), throwsA(isA<WalletException>().having((e) => e.message, 'message', 'WRONG_PASSWORD')));
    });

    test('shutdown closes the open wallet, then stops the engine', () async {
      await openIt();
      await core.shutdown();
      expect(api.calls.sublist(api.calls.length - 2), ['close 9', 'shutdown']);
      await core.shutdown(); // idempotent: nothing open, engine stopped again without error
      expect(api.calls.last, 'shutdown');
    });

    test('calls need an open wallet', () async {
      expect(core.balances(), throwsA(isA<WalletException>()));
      expect(core.syncProgress(), throwsA(isA<WalletException>()));
    });

    test('close releases the handle', () async {
      await openIt();
      await core.closeWallet();
      expect(api.calls.last, 'close 9');
      expect(core.address(), throwsA(isA<WalletException>()));
    });
  });

  group('queries', () {
    test('balances map asset info and keep 64-bit totals exact', () async {
      api.rpc['getbalance'] = (_) => '{"balance":1,"unlocked_balance":1,"balances":['
          '{"asset_info":{"asset_id":"${AssetId.native.hex}","ticker":"PDC","full_name":"PDC","decimal_point":12},"total":18446744073709551615,"unlocked":9007199254740993},'
          '{"asset_info":{"asset_id":"a5ff","ticker":"GOLD","full_name":"Gold","decimal_point":2},"total":150,"unlocked":150}]}';
      await openIt();
      final b = await core.balances();
      expect(b.length, 2);
      expect(b[0].assetId.isNative, isTrue);
      expect(b[0].total.atomic, BigInt.parse('18446744073709551615'));
      expect(b[0].unlocked.atomic, BigInt.parse('9007199254740993'));
      expect(b[1].ticker, 'GOLD');
      expect(b[1].formatTotal(), '1.5');
    });

    test('sync progress comes from wallet and daemon heights', () async {
      await openIt();
      expect(await core.syncProgress(), 0.25);
      api.statusReply = '{"current_wallet_height":300,"current_daemon_height":200}';
      expect(await core.syncProgress(), 1.0);
      api.statusReply = '{"current_wallet_height":0,"current_daemon_height":0}';
      expect(await core.syncProgress(), 0.0);
    });

    test('history yields one entry per asset in a transaction', () async {
      api.rpc['get_recent_txs_and_info2'] = (_) => '{"transfers":[{"tx_hash":"ab12","height":10,"timestamp":1700000000,"fee":10000000000,'
          '"comment":"hi","subtransfers":[{"amount":5,"is_income":true,"asset_id":"${AssetId.native.hex}"},'
          '{"amount":7,"is_income":false,"asset_id":"a5ff"}]}],"total_transfers":1,"last_item_index":0}';
      await openIt();
      final h = await core.history(offset: 0, count: 20);
      expect(h.length, 2);
      expect(h[0].isIncoming, isTrue);
      expect(h[0].amount.atomic, BigInt.from(5));
      expect(h[1].isIncoming, isFalse);
      expect(h[1].assetId.hex, 'a5ff');
      expect(h[0].timestamp.toUtc().year, 2023);
      final req = api.invoked.last['params'] as Map;
      expect(req['count'], 20);
      expect(req['order'], 'FROM_END_TO_BEGIN');
    });
  });

  group('BUSY while the wallet refreshes', () {
    test('calls are retried until the wallet answers', () async {
      var busy = 2;
      api.rpc['getbalance'] = (_) => '{"balance":0,"unlocked_balance":0,"balances":[]}';
      final wrapped = _BusyApi(api, () => busy-- > 0);
      final c = InvokeWalletCore(wrapped, workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
      await c.connect(NodeEndpoint('https://node.example.org'));
      await c.openWallet(name: 'w', password: 'pw');
      expect(await c.balances(), isEmpty);
      expect(wrapped.busyAnswers, 2);
    });

    test('gives up with BUSY after the retry limit', () async {
      final c = InvokeWalletCore(_BusyApi(api, () => true), workingDir: '/data', busyDelay: Duration.zero, busyRetries: 3);
      await c.openWallet(name: 'w', password: 'pw');
      await expectLater(c.balances(), throwsA(isA<WalletException>().having((e) => e.message, 'message', 'BUSY')));
    });

    test('other errors are not retried', () async {
      await openIt();
      final before = api.invoked.length;
      await expectLater(core.balances(), throwsA(isA<WalletException>())); // no getbalance handler: method not found
      expect(api.invoked.length, before + 1);
    });
  });

  group('transactions', () {
    test('send builds a transfer with exact atomic amounts and the default fee', () async {
      api.rpc['transfer'] = (_) => '{"tx_hash":"deadbeef","tx_size":100}';
      await openIt();
      final tx = await core.send(toAddress: 'PxDEST', amount: Amount.parse('18446744.073709551615'));
      expect(tx, 'deadbeef');
      final p = api.invoked.last['params'] as Map;
      final d = (p['destinations'] as List).single as Map;
      expect(d['address'], 'PxDEST');
      expect(asBigInt(d['amount']), BigInt.parse('18446744073709551615'));
      expect(d['asset_id'], AssetId.native.hex);
      expect(p['fee'], 10000000000);
      expect(p['mixin'], 15);
    });

    test('send rejects zero and surfaces wallet errors', () async {
      await openIt();
      expect(core.send(toAddress: 'PxDEST', amount: Amount.zero), throwsA(isA<WalletException>()));
      api.rpc.remove('transfer');
      expect(core.send(toAddress: 'PxDEST', amount: Amount.parse('1')), throwsA(isA<WalletException>()));
    });

    test('deployAsset sends the descriptor, omits owner, and emits the initial supply to the wallet', () async {
      api.rpc['deploy_asset'] = (_) => '{"tx_id":"11aa","new_asset_id":"a5beef"}';
      await openIt();
      final draft = AssetDraft(
        ticker: 'GOLD',
        fullName: 'Gold Token',
        metaInfo: 'shiny',
        decimalPoint: 12,
        totalMaxSupply: BigInt.parse('18446744073709551615'),
        initialSupply: BigInt.parse('9007199254740993'),
      );
      final r = await core.deployAsset(draft);
      expect(r.txId, '11aa');
      expect(r.assetId.hex, 'a5beef');
      final p = api.invoked.last['params'] as Map;
      final descr = p['asset_descriptor'] as Map;
      expect(descr['ticker'], 'GOLD');
      expect(descr['decimal_point'], 12);
      expect(descr['total_max_supply'], BigInt.parse('18446744073709551615'));
      expect(descr['current_supply'], BigInt.parse('9007199254740993'));
      expect(descr.containsKey('owner'), isFalse);
      expect(descr['hidden_supply'], false);
      final dest = (p['destinations'] as List).single as Map;
      expect(dest['address'], 'PxADDRESS');
      expect(dest['amount'], BigInt.parse('9007199254740993'));
    });

    test('deployAsset validates before calling the engine', () async {
      await openIt();
      final bad = AssetDraft(ticker: 'NOT VALID', fullName: '', decimalPoint: 12, totalMaxSupply: BigInt.one, initialSupply: BigInt.one);
      expect(core.deployAsset(bad), throwsA(isA<WalletException>()));
      expect(api.invoked.where((r) => r['method'] == 'deploy_asset'), isEmpty);
    });

    test('addCustomAsset whitelists by id and reports an unknown asset', () async {
      api.rpc['assets_whitelist_add'] = (p) => p['asset_id'] == 'a5beef' ? '{"status":"OK","asset_descriptor":{}}' : '{"status":"NOT_FOUND"}';
      await openIt();
      await core.addCustomAsset(const AssetId('a5beef'));
      expect((api.invoked.last['params'] as Map)['asset_id'], 'a5beef');
      await expectLater(core.addCustomAsset(const AssetId('ffff')),
          throwsA(isA<WalletException>().having((e) => e.message, 'message', 'NOT_FOUND')));
    });

    test('emit and burn use the asset id and exact amounts', () async {
      api.rpc['emit_asset'] = (_) => '{"tx_id":"e1"}';
      api.rpc['burn_asset'] = (_) => '{"tx_id":"b1"}';
      await openIt();
      const id = AssetId('a5beef');
      expect(await core.emitAsset(asset: id, amount: Amount.parse('2.5', decimals: 2)), 'e1');
      var p = api.invoked.last['params'] as Map;
      expect(p['asset_id'], 'a5beef');
      expect(asBigInt(((p['destinations'] as List).single as Map)['amount']), BigInt.from(250));
      expect(await core.burnAsset(asset: id, amount: Amount.fromAtomic(BigInt.from(100))), 'b1');
      p = api.invoked.last['params'] as Map;
      expect(asBigInt(p['burn_amount']), BigInt.from(100));
      expect(core.burnAsset(asset: id, amount: Amount.zero), throwsA(isA<WalletException>()));
    });
  });
}

/// Answers invoke() with BUSY while [busy] says so, otherwise delegates to [inner].
class _BusyApi implements RawWalletApi {
  _BusyApi(this.inner, this.busy);
  final FakeRawApi inner;
  final bool Function() busy;
  int busyAnswers = 0;

  @override
  Future<String> invoke(int walletId, String jsonRpcRequest) async {
    if (busy()) {
      busyAnswers++;
      return '{"id":0,"jsonrpc":"2.0","error":{"code":-1,"message":"BUSY"}}';
    }
    return inner.invoke(walletId, jsonRpcRequest);
  }

  @override
  Future<String> init(String nodeAddress, String workingDir, int logLevel) => inner.init(nodeAddress, workingDir, logLevel);
  @override
  Future<String> generate(String path, String password) => inner.generate(path, password);
  @override
  Future<String> restore(String seed, String path, String password, String seedPassword) => inner.restore(seed, path, password, seedPassword);
  @override
  Future<String> open(String path, String password) => inner.open(path, password);
  @override
  Future<String> closeWallet(int walletId) => inner.closeWallet(walletId);
  @override
  Future<String> getWalletStatus(int walletId) => inner.getWalletStatus(walletId);
  @override
  Future<String> shutdown() => inner.shutdown();
}
