// WalletCore implemented over RawWalletApi: translates the UI's calls into wallet RPC requests
// (src/wallet/wallet_rpc_server.h: getbalance, getaddress, transfer, get_recent_txs_and_info2, deploy_asset,
// emit_asset, burn_asset) and the replies back into Dart types. No crypto or networking happens here; that is all
// in the C++ engine behind RawWalletApi. 64-bit amounts always go through the exact JSON codec.

import '../core/amount.dart';
import '../core/asset_rules.dart';
import '../core/json_exact.dart';
import 'raw_wallet_api.dart';
import 'wallet_core.dart';

class InvokeWalletCore implements WalletCore {
  InvokeWalletCore(this._api, {required this.workingDir});

  final RawWalletApi _api;

  /// Directory the engine keeps wallet files in (app data dir on desktop, a virtual FS on the web).
  final String workingDir;

  int? _wallet;
  int _id = 0;
  String? _cachedAddress;

  /// Mandatory decoy set size since HF4 (CURRENCY_HF4_MANDATORY_DECOY_SET_SIZE); the engine enforces it anyway.
  static const int _mixin = 15;

  @override
  Future<void> connect(NodeEndpoint node) async {
    final reply = await _api.init(node.url, workingDir, 0);
    _throwIfError(reply, allowBareOk: true);
  }

  @override
  Future<String> createWallet({required String name, required String password}) async {
    final result = _result(await _api.generate(name, password));
    _wallet = _walletIdOf(result);
    _cachedAddress = null;
    final seed = result['seed'];
    if (seed is! String || seed.isEmpty) throw WalletException('engine did not return a recovery phrase');
    return seed;
  }

  @override
  Future<void> restoreWallet({
    required String name,
    required String password,
    required String seedPhrase,
    String seedPassword = '',
  }) async {
    final result = _result(await _api.restore(seedPhrase, name, password, seedPassword));
    _wallet = _walletIdOf(result);
    _cachedAddress = null;
  }

  @override
  Future<void> openWallet({required String name, required String password}) async {
    final result = _result(await _api.open(name, password));
    _wallet = _walletIdOf(result);
    _cachedAddress = null;
  }

  @override
  Future<void> closeWallet() async {
    final w = _wallet;
    if (w == null) return;
    await _api.closeWallet(w);
    _wallet = null;
    _cachedAddress = null;
  }

  @override
  Future<String> address() async {
    final cached = _cachedAddress;
    if (cached != null) return cached;
    final r = await _call('getaddress');
    final a = r['address'];
    if (a is! String || a.isEmpty) throw WalletException('wallet returned no address');
    return _cachedAddress = a;
  }

  @override
  Future<List<AssetBalance>> balances() async {
    final r = await _call('getbalance');
    final list = r['balances'];
    if (list is! List) return const [];
    final out = <AssetBalance>[];
    for (final e in list) {
      if (e is! Map<String, Object?>) continue;
      final info = e['asset_info'];
      if (info is! Map<String, Object?>) continue;
      final id = info['asset_id'];
      if (id is! String) continue;
      final decimals = _smallInt(info['decimal_point']);
      out.add(AssetBalance(
        assetId: AssetId(id),
        ticker: (info['ticker'] as String?) ?? '',
        fullName: (info['full_name'] as String?) ?? '',
        decimalPoint: decimals,
        total: Amount.fromAtomic(asBigInt(e['total']) ?? BigInt.zero),
        unlocked: Amount.fromAtomic(asBigInt(e['unlocked']) ?? BigInt.zero),
      ));
    }
    return out;
  }

  @override
  Future<double> syncProgress() async {
    final w = _requireWallet();
    final decoded = decodeJsonExact(await _api.getWalletStatus(w));
    if (decoded is! Map<String, Object?>) return 0;
    final wallet = _smallInt(decoded['current_wallet_height']);
    final daemon = _smallInt(decoded['current_daemon_height']);
    if (daemon <= 0) return 0;
    final p = wallet / daemon;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  @override
  Future<List<WalletTx>> history({int offset = 0, int count = 50}) async {
    final r = await _call('get_recent_txs_and_info2', {
      'offset': offset,
      'count': count,
      'update_provision_info': false,
      'exclude_mining_txs': false,
      'exclude_unconfirmed': false,
      'order': 'FROM_END_TO_BEGIN',
    });
    final transfers = r['transfers'];
    if (transfers is! List) return const [];
    final out = <WalletTx>[];
    for (final t in transfers) {
      if (t is! Map<String, Object?>) continue;
      final subs = t['subtransfers'];
      if (subs is! List) continue;
      final fee = Amount.fromAtomic(asBigInt(t['fee']) ?? BigInt.zero);
      final ts = DateTime.fromMillisecondsSinceEpoch(_smallInt(t['timestamp']) * 1000, isUtc: true);
      // one entry per asset moved by the transaction
      for (final s in subs) {
        if (s is! Map<String, Object?>) continue;
        out.add(WalletTx(
          txHash: (t['tx_hash'] as String?) ?? '',
          height: _smallInt(t['height']),
          timestamp: ts,
          isIncoming: s['is_income'] == true,
          amount: Amount.fromAtomic(asBigInt(s['amount']) ?? BigInt.zero),
          assetId: AssetId((s['asset_id'] as String?) ?? AssetId.native.hex),
          fee: fee,
          comment: (t['comment'] as String?) ?? '',
        ));
      }
    }
    return out;
  }

  @override
  Future<String> send({
    required String toAddress,
    required Amount amount,
    AssetId asset = AssetId.native,
    Amount? fee,
    String comment = '',
  }) async {
    if (amount.isZero) throw WalletException('amount must be greater than zero');
    final r = await _call('transfer', {
      'destinations': [
        {'address': toAddress, 'amount': amount.atomic, 'asset_id': asset.hex},
      ],
      'fee': (fee ?? defaultFee).atomic,
      'mixin': _mixin,
      'payment_id': '',
      'comment': comment,
      'push_payer': false,
      'hide_receiver': false,
    });
    final h = r['tx_hash'];
    if (h is! String || h.isEmpty) throw WalletException('wallet did not return a transaction id');
    return h;
  }

  @override
  Future<DeployedAsset> deployAsset(AssetDraft draft) async {
    final problems = AssetRules.validate(draft);
    if (problems.isNotEmpty) throw WalletException(problems.first);
    final me = await address();
    // `owner` is left out on purpose: the wallet sets it to this wallet's key when it builds the registration.
    final r = await _call('deploy_asset', {
      'asset_descriptor': {
        'ticker': draft.ticker,
        'full_name': draft.fullName,
        'meta_info': draft.metaInfo,
        'decimal_point': draft.decimalPoint,
        'total_max_supply': draft.totalMaxSupply,
        'current_supply': draft.initialSupply,
        'hidden_supply': draft.hiddenSupply,
      },
      // the initial supply is emitted to the deployer; the asset id in a destination is irrelevant for registration
      'destinations': [
        {'address': me, 'amount': draft.initialSupply},
      ],
      'do_not_split_destinations': false,
    });
    final tx = r['tx_id'];
    final id = r['new_asset_id'];
    if (tx is! String || id is! String) throw WalletException('wallet did not return the new asset id');
    return DeployedAsset(txId: tx, assetId: AssetId(id));
  }

  @override
  Future<String> emitAsset({required AssetId asset, required Amount amount}) async {
    if (amount.isZero) throw WalletException('amount must be greater than zero');
    final me = await address();
    final r = await _call('emit_asset', {
      'asset_id': asset.hex,
      'destinations': [
        {'address': me, 'amount': amount.atomic},
      ],
      'do_not_split_destinations': false,
    });
    return _txIdOf(r);
  }

  @override
  Future<String> burnAsset({required AssetId asset, required Amount amount}) async {
    if (amount.isZero) throw WalletException('amount must be greater than zero');
    final r = await _call('burn_asset', {'asset_id': asset.hex, 'burn_amount': amount.atomic});
    return _txIdOf(r);
  }

  // ---- plumbing ----

  int _requireWallet() {
    final w = _wallet;
    if (w == null) throw WalletException('no wallet is open');
    return w;
  }

  Future<Map<String, Object?>> _call(String method, [Map<String, Object?> params = const {}]) async {
    final w = _requireWallet();
    final request = encodeJsonExact({'jsonrpc': '2.0', 'id': _id++, 'method': method, 'params': params});
    return _result(await _api.invoke(w, request));
  }

  static String _txIdOf(Map<String, Object?> r) {
    final h = r['tx_id'] ?? r['tx_hash'];
    if (h is! String || h.isEmpty) throw WalletException('wallet did not return a transaction id');
    return h;
  }

  static int _walletIdOf(Map<String, Object?> result) {
    final id = result['wallet_id'];
    if (id is int) return id;
    throw WalletException('engine did not return a wallet handle');
  }

  /// Parses a JSON-RPC style reply and returns `result`, or throws the engine's error.
  static Map<String, Object?> _result(String reply) {
    final decoded = _decode(reply);
    final err = decoded['error'];
    if (err != null) throw _errorOf(err);
    final result = decoded['result'];
    if (result is! Map<String, Object?>) throw WalletException('engine returned no result');
    return result;
  }

  static void _throwIfError(String reply, {bool allowBareOk = false}) {
    final t = reply.trim();
    if (allowBareOk && (t == 'OK' || t == '"OK"')) return;
    final decoded = _decode(reply);
    final err = decoded['error'];
    if (err != null) throw _errorOf(err);
  }

  static Map<String, Object?> _decode(String reply) {
    final Object? decoded;
    try {
      decoded = decodeJsonExact(reply);
    } on JsonExactException {
      // some engine calls answer with a bare status word such as BAD_ARG
      throw WalletException(reply.trim().isEmpty ? 'engine returned an empty reply' : reply.trim());
    }
    if (decoded is! Map<String, Object?>) throw WalletException('engine returned an unexpected reply');
    return decoded;
  }

  static WalletException _errorOf(Object err) {
    if (err is Map) {
      final code = err['code'];
      final message = err['message'];
      return WalletException(
        (message is String && message.isNotEmpty) ? message : '${code ?? 'unknown error'}',
        code: code is int ? code : null,
      );
    }
    return WalletException('$err');
  }

  static int _smallInt(Object? v) {
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    return 0;
  }
}
