import 'package:flutter/foundation.dart';

import '../core/amount.dart';
import '../core/asset_rules.dart';
import '../wallet/wallet_core.dart';

/// App state shared by the screens. Talks only to [WalletCore], so it works the same with the demo engine and the
/// real one.
class WalletController extends ChangeNotifier {
  WalletController(this.core, {NodeEndpoint? node, required this.isDemoEngine})
      : node = node ?? NodeEndpoint('http://127.0.0.1:19211');

  final WalletCore core;

  /// True while the in-memory demo engine is in use: balances are fake and nothing touches the network.
  final bool isDemoEngine;

  NodeEndpoint node;
  bool isOpen = false;
  bool busy = false;
  String address = '';
  double syncProgress = 0;
  List<AssetBalance> balances = const [];
  List<WalletTx> history = const [];

  Future<T> _guard<T>(Future<T> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setNode(NodeEndpoint endpoint) async {
    await _guard(() => core.connect(endpoint));
    node = endpoint;
  }

  /// Returns the recovery phrase; the caller must make the user write it down before continuing.
  Future<String> createWallet(String name, String password) => _guard(() async {
        await core.connect(node);
        final seed = await core.createWallet(name: name, password: password);
        await _afterOpen();
        return seed;
      });

  Future<void> restoreWallet(String name, String password, String seed, String seedPassword) => _guard(() async {
        await core.connect(node);
        await core.restoreWallet(name: name, password: password, seedPhrase: seed, seedPassword: seedPassword);
        await _afterOpen();
      });

  Future<void> openWallet(String name, String password) => _guard(() async {
        await core.connect(node);
        await core.openWallet(name: name, password: password);
        await _afterOpen();
      });

  /// Called when the application is about to exit.
  Future<void> shutdown() => core.shutdown();

  Future<void> lock() async {
    await core.closeWallet();
    isOpen = false;
    balances = const [];
    history = const [];
    address = '';
    notifyListeners();
  }

  Future<void> _afterOpen() async {
    isOpen = true;
    address = await core.address();
    await _refresh();
  }

  Future<void> refresh() => _guard(_refresh);

  Future<void> _refresh() async {
    syncProgress = await core.syncProgress();
    balances = await core.balances();
    history = await core.history();
  }

  Future<String> send(String to, Amount amount, AssetId asset, String comment) => _guard(() async {
        final tx = await core.send(toAddress: to.trim(), amount: amount, asset: asset, comment: comment);
        await _refresh();
        return tx;
      });

  Future<void> addCustomAsset(AssetId asset) => _guard(() async {
        await core.addCustomAsset(asset);
        await _refresh();
      });

  Future<DeployedAsset> deployAsset(AssetDraft draft) => _guard(() async {
        final r = await core.deployAsset(draft);
        await _refresh();
        return r;
      });

  Future<String> emitAsset(AssetId asset, Amount amount) => _guard(() async {
        final tx = await core.emitAsset(asset: asset, amount: amount);
        await _refresh();
        return tx;
      });

  Future<String> burnAsset(AssetId asset, Amount amount) => _guard(() async {
        final tx = await core.burnAsset(asset: asset, amount: amount);
        await _refresh();
        return tx;
      });

  AssetBalance? get nativeBalance {
    for (final b in balances) {
      if (b.assetId.isNative) return b;
    }
    return null;
  }

  /// Whether the wallet can pay the fee for an asset operation right now.
  bool get canPayFee {
    final n = nativeBalance;
    return n != null && n.unlocked >= defaultFee;
  }
}
