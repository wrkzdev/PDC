// The boundary between the Flutter UI and the wallet engine.
//
// The real engine is the C++ wallet (wallet2) built in its remote-only mode and driven through the string-in /
// string-out plain_wallet_api: a native library over dart:ffi on desktop (and later mobile), the same code compiled
// to WebAssembly on the web. The UI only sees this interface, so it can be developed and tested against
// MockWalletCore and the real engines are drop-in replacements. See docs/wallet/PLAN.md.

import '../core/amount.dart';
import '../core/asset_rules.dart';

class AssetId {
  const AssetId(this.hex);
  final String hex;

  /// Id of the native coin (currency::native_coin_asset_id in currency_basic.h, the curve point H).
  static const AssetId native = AssetId('d6329b5b1f7c0805b5c345f4957554002a2f557845f64d7645dae0e051a6498a');

  bool get isNative => this == native;

  @override
  bool operator ==(Object other) => other is AssetId && other.hex == hex;
  @override
  int get hashCode => hex.hashCode;
  @override
  String toString() => hex;
}

class AssetBalance {
  const AssetBalance({
    required this.assetId,
    required this.ticker,
    required this.fullName,
    required this.decimalPoint,
    required this.total,
    required this.unlocked,
  });

  final AssetId assetId;
  final String ticker;
  final String fullName;
  final int decimalPoint;
  final Amount total;
  final Amount unlocked;

  String formatTotal() => total.format(decimals: decimalPoint);
  String formatUnlocked() => unlocked.format(decimals: decimalPoint);
}

class WalletTx {
  const WalletTx({
    required this.txHash,
    required this.height,
    required this.timestamp,
    required this.isIncoming,
    required this.amount,
    required this.assetId,
    required this.fee,
    this.comment = '',
  });

  final String txHash;
  final int height; // 0 while unconfirmed
  final DateTime timestamp;
  final bool isIncoming;
  final Amount amount;
  final AssetId assetId;
  final Amount fee;
  final String comment;
}

class DeployedAsset {
  const DeployedAsset({required this.txId, required this.assetId});
  final String txId;
  final AssetId assetId;
}

/// Where the engine syncs from. A remote node is a PDC daemon, normally reached through the public-node gateway.
class NodeEndpoint {
  NodeEndpoint(this.url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty || (u.scheme != 'http' && u.scheme != 'https')) {
      throw FormatException('node address must be an http(s) URL', url);
    }
  }

  final String url;
  Uri get uri => Uri.parse(url);

  /// Plain HTTP is only acceptable on loopback; anywhere else the traffic (which reveals what the wallet is
  /// scanning for) and the transactions you send would travel in the clear.
  bool get isSecureEnough {
    final u = uri;
    if (u.scheme == 'https') return true;
    final h = u.host;
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  }
}

class WalletException implements Exception {
  WalletException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'WalletException($message${code == null ? '' : ', code $code'})';
}

abstract class WalletCore {
  /// Connects the engine to a node. Must be called before opening a wallet.
  Future<void> connect(NodeEndpoint node);

  /// Creates a wallet and returns its 24-word recovery phrase for the user to write down.
  Future<String> createWallet({required String name, required String password});

  Future<void> restoreWallet({
    required String name,
    required String password,
    required String seedPhrase,
    String seedPassword = '',
  });

  Future<void> openWallet({required String name, required String password});
  Future<void> closeWallet();

  Future<String> address();

  /// Balances for the native coin and every known asset.
  Future<List<AssetBalance>> balances();

  /// Fraction of the chain scanned, 0..1.
  Future<double> syncProgress();

  Future<List<WalletTx>> history({int offset = 0, int count = 50});

  Future<String> send({
    required String toAddress,
    required Amount amount,
    AssetId asset = AssetId.native,
    Amount? fee,
    String comment = '',
  });

  /// Registers a new asset and emits [AssetDraft.initialSupply] to this wallet. Pays only the normal fee.
  Future<DeployedAsset> deployAsset(AssetDraft draft);

  /// Emits more of an asset this wallet owns, up to its maximum supply.
  Future<String> emitAsset({required AssetId asset, required Amount amount});

  /// Destroys [amount] of an asset this wallet holds (public burn).
  Future<String> burnAsset({required AssetId asset, required Amount amount});
}
