import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/amount.dart';
import '../core/asset_rules.dart';
import '../wallet/wallet_core.dart';
import 'app_settings.dart';

/// App state shared by the screens. Talks only to [WalletCore], so it works the same with the demo engine and the
/// real one.
class WalletController extends ChangeNotifier {
  /// [pollInterval] is how often balances, history and sync state are re-read while a wallet is open; null turns
  /// polling off (tests drive [refresh] by hand).
  WalletController(
    this.core, {
    NodeEndpoint? node,
    required this.isDemoEngine,
    this.pollInterval,
    AppSettings? settings,
  }) : settings = settings ?? AppSettings.memory(),
       node =
           node ??
           _savedNode(settings) ??
           NodeEndpoint('http://127.0.0.1:19211');

  /// The node saved by an earlier run, if it still parses.
  static NodeEndpoint? _savedNode(AppSettings? s) {
    final url = s?.nodeUrl;
    if (url == null) return null;
    try {
      return NodeEndpoint(url);
    } on FormatException {
      return null;
    }
  }

  final AppSettings settings;

  final WalletCore core;
  final Duration? pollInterval;

  /// True while the in-memory demo engine is in use: balances are fake and nothing touches the network.
  final bool isDemoEngine;

  NodeEndpoint node;
  bool isOpen = false;
  bool busy = false;
  String address = '';
  double syncProgress = 0;
  List<AssetBalance> balances = const [];
  List<WalletTx> history = const [];

  /// When the wallet state was last read successfully, and the error of the last failed background read (cleared by
  /// the next success). Lets the UI say "updated 5 s ago" or "node unreachable" instead of showing stale data silently.
  DateTime? lastUpdated;
  String? refreshError;

  Timer? _poll;
  bool _polling = false;
  bool _foreground = true;

  /// True once the wallet has scanned the whole chain it knows of.
  bool get isSynced => syncProgress >= 1;

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
    settings.nodeUrl = endpoint.url;
    await settings.save();
  }

  /// Name of the wallet opened last time, so the welcome screen can offer "Open" first.
  String? get lastWalletName => settings.lastWalletName;

  ThemeMode get themeMode => settings.themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    settings.themeMode = mode;
    notifyListeners();
    await settings.save();
  }

  Future<void> _remember(String name) async {
    settings.nodeUrl = node.url;
    settings.lastWalletName = name;
    await settings.save();
  }

  /// Returns the recovery phrase; the caller must make the user write it down before continuing.
  Future<String> createWallet(String name, String password) => _guard(() async {
    await core.connect(node);
    final seed = await core.createWallet(name: name, password: password);
    await _afterOpen();
    await _remember(name);
    return seed;
  });

  Future<void> restoreWallet(
    String name,
    String password,
    String seed,
    String seedPassword,
  ) => _guard(() async {
    await core.connect(node);
    await core.restoreWallet(
      name: name,
      password: password,
      seedPhrase: seed,
      seedPassword: seedPassword,
    );
    await _afterOpen();
    await _remember(name);
  });

  Future<void> restoreWalletFromKeys(
    String name,
    String password,
    String spendKey,
    String viewKey,
  ) => _guard(() async {
    await core.connect(node);
    await core.restoreWalletFromKeys(
      name: name,
      password: password,
      spendKey: spendKey,
      viewKey: viewKey,
    );
    await _afterOpen();
    await _remember(name);
  });

  Future<void> openWallet(String name, String password) => _guard(() async {
    await core.connect(node);
    await core.openWallet(name: name, password: password);
    await _afterOpen();
    await _remember(name);
  });

  /// Called when the application is about to exit.
  Future<void> shutdown() {
    _stopPolling();
    return core.shutdown();
  }

  /// Polling pauses while the app is in the background and catches up as soon as it returns.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground && isOpen) unawaited(_pollOnce());
  }

  void _startPolling() {
    _poll?.cancel();
    final every = pollInterval;
    if (every == null) return;
    _poll = Timer.periodic(every, (_) => unawaited(_pollOnce()));
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// A background read: never shows the busy state, never overlaps another read, and keeps the last good data on
  /// failure. Notifies only when something changed so an idle wallet does not repaint every few seconds.
  Future<void> _pollOnce() async {
    if (!isOpen || busy || _polling || !_foreground) return;
    _polling = true;
    try {
      final snap = await _read();
      // The wallet may have been locked, or an action started, while the read was in flight.
      if (!isOpen || busy) return;
      final changed =
          snap.progress != syncProgress ||
          !listEquals(snap.balances, balances) ||
          !listEquals(snap.history, history) ||
          refreshError != null;
      _apply(snap);
      if (changed) notifyListeners();
    } on Object catch (e) {
      if (!isOpen) return;
      final msg = e.toString();
      if (refreshError != msg) {
        refreshError = msg;
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> lock() async {
    _stopPolling();
    await core.closeWallet();
    isOpen = false;
    syncProgress = 0;
    lastUpdated = null;
    refreshError = null;
    balances = const [];
    history = const [];
    address = '';
    notifyListeners();
  }

  Future<void> _afterOpen() async {
    isOpen = true;
    address = await core.address();
    await _refresh();
    _startPolling();
  }

  Future<void> refresh() => _guard(_refresh);

  Future<void> _refresh() async => _apply(await _read());

  Future<
    ({double progress, List<AssetBalance> balances, List<WalletTx> history})
  >
  _read() async {
    final progress = await core.syncProgress();
    final balances = await core.balances();
    final history = await core.history();
    return (progress: progress, balances: balances, history: history);
  }

  void _apply(
    ({double progress, List<AssetBalance> balances, List<WalletTx> history}) s,
  ) {
    syncProgress = s.progress;
    balances = s.balances;
    history = s.history;
    refreshError = null;
    lastUpdated = DateTime.now();
  }

  Future<String> send(
    String to,
    Amount amount,
    AssetId asset,
    String comment,
  ) => _guard(() async {
    final tx = await core.send(
      toAddress: to.trim(),
      amount: amount,
      asset: asset,
      comment: comment,
    );
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
