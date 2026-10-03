// In-memory WalletCore for developing and testing the UI before the native engine is wired in. It moves fake
// balances around with the same rules the real wallet applies (fee, at least one confirmed native coin for asset
// operations, supply limits) but has no keys, no chain and no cryptography: NEVER use it with real funds.

import '../core/amount.dart';
import '../core/asset_rules.dart';
import 'wallet_core.dart';

class MockWalletCore implements WalletCore {
  MockWalletCore({Amount? startingBalance})
      : _native = startingBalance ?? Amount.parse('100');

  Amount _native;
  bool _open = false;
  int _txCounter = 0;
  final Map<String, _MockAsset> _assets = {};
  final List<WalletTx> _history = [];
  NodeEndpoint? node;

  static const String _address =
      'PxMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCK';

  @override
  Future<void> connect(NodeEndpoint node) async => this.node = node;

  @override
  Future<String> createWallet({required String name, required String password}) async {
    _open = true;
    return List.generate(24, (i) => 'mock${i + 1}').join(' ');
  }

  @override
  Future<void> restoreWallet({
    required String name,
    required String password,
    required String seedPhrase,
    String seedPassword = '',
  }) async {
    if (seedPhrase.trim().split(RegExp(r'\s+')).length != 24) {
      throw WalletException('a recovery phrase has 24 words');
    }
    _open = true;
  }

  @override
  Future<void> openWallet({required String name, required String password}) async => _open = true;

  @override
  Future<void> closeWallet() async => _open = false;

  void _requireOpen() {
    if (!_open) throw WalletException('no wallet is open');
  }

  @override
  Future<String> address() async {
    _requireOpen();
    return _address;
  }

  @override
  Future<List<AssetBalance>> balances() async {
    _requireOpen();
    return [
      AssetBalance(
        assetId: AssetId.native,
        ticker: 'PDC',
        fullName: 'PDC',
        decimalPoint: nativeDecimals,
        total: _native,
        unlocked: _native,
      ),
      for (final a in _assets.values)
        AssetBalance(
          assetId: a.id,
          ticker: a.draft.ticker,
          fullName: a.draft.fullName,
          decimalPoint: a.draft.decimalPoint,
          total: Amount.fromAtomic(a.held),
          unlocked: Amount.fromAtomic(a.held),
        ),
    ];
  }

  @override
  Future<double> syncProgress() async => 1;

  @override
  Future<List<WalletTx>> history({int offset = 0, int count = 50}) async {
    _requireOpen();
    final newestFirst = _history.reversed.toList();
    if (offset >= newestFirst.length) return const [];
    return newestFirst.skip(offset).take(count).toList();
  }

  void _payFee(Amount fee) {
    if (_native < fee) throw WalletException('not enough PDC to pay the network fee');
    _native = _native - fee;
  }

  String _record({required bool incoming, required Amount amount, required AssetId asset, required Amount fee, String comment = ''}) {
    final hash = (++_txCounter).toRadixString(16).padLeft(64, '0');
    _history.add(WalletTx(
      txHash: hash,
      height: 1000 + _txCounter,
      timestamp: DateTime.now().toUtc(),
      isIncoming: incoming,
      amount: amount,
      assetId: asset,
      fee: fee,
      comment: comment,
    ));
    return hash;
  }

  @override
  Future<String> send({
    required String toAddress,
    required Amount amount,
    AssetId asset = AssetId.native,
    Amount? fee,
    String comment = '',
  }) async {
    _requireOpen();
    if (!toAddress.startsWith('Px')) throw WalletException('not a PDC address');
    if (amount.isZero) throw WalletException('amount must be greater than zero');
    final f = fee ?? defaultFee;
    if (asset.isNative) {
      if (_native < amount + f) throw WalletException('not enough PDC');
      _native = _native - amount;
    } else {
      final a = _assets[asset.hex];
      if (a == null || a.held < amount.atomic) throw WalletException('not enough of this asset');
      a.held -= amount.atomic;
    }
    _payFee(f);
    return _record(incoming: false, amount: amount, asset: asset, fee: f, comment: comment);
  }

  @override
  Future<DeployedAsset> deployAsset(AssetDraft draft) async {
    _requireOpen();
    final problems = AssetRules.validate(draft);
    if (problems.isNotEmpty) throw WalletException(problems.first);
    final id = AssetId(_fakeId(_assets.length + 1));
    _payFee(defaultFee);
    _assets[id.hex] = _MockAsset(id, draft, draft.initialSupply, draft.initialSupply);
    final tx = _record(incoming: true, amount: Amount.fromAtomic(draft.initialSupply), asset: id, fee: defaultFee, comment: 'asset registration');
    return DeployedAsset(txId: tx, assetId: id);
  }

  @override
  Future<String> emitAsset({required AssetId asset, required Amount amount}) async {
    _requireOpen();
    final a = _assets[asset.hex];
    if (a == null) throw WalletException('this wallet does not own that asset');
    if (a.emitted + amount.atomic > a.draft.totalMaxSupply) throw WalletException('would exceed the maximum supply');
    _payFee(defaultFee);
    a.emitted += amount.atomic;
    a.held += amount.atomic;
    return _record(incoming: true, amount: amount, asset: asset, fee: defaultFee, comment: 'asset emission');
  }

  @override
  Future<String> burnAsset({required AssetId asset, required Amount amount}) async {
    _requireOpen();
    final a = _assets[asset.hex];
    if (a == null || a.held < amount.atomic) throw WalletException('not enough of this asset to burn');
    _payFee(defaultFee);
    a.held -= amount.atomic;
    a.emitted -= amount.atomic;
    return _record(incoming: false, amount: amount, asset: asset, fee: defaultFee, comment: 'asset burn');
  }

  static String _fakeId(int n) => 'a5${n.toRadixString(16).padLeft(62, '0')}';
}

class _MockAsset {
  _MockAsset(this.id, this.draft, this.held, this.emitted);
  final AssetId id;
  final AssetDraft draft;
  BigInt held;
  BigInt emitted;
}
