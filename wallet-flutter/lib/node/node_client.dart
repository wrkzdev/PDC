// Read-only client for a PDC node, spoken through the public-node gateway (utils/docker/gateway) or a local daemon.
//
// Only methods the gateway allowlist forwards are used here (see utils/docker/gateway/gateway.js). It is plain
// Dart over package:http, so it works on desktop and in the browser (the gateway adds CORS). The wallet engine
// does its own block scanning; this client is for what the UI needs around it: node health, fees and asset lookups.

import 'package:http/http.dart' as http;

import '../core/amount.dart';
import '../core/asset_rules.dart' show defaultFee;
import '../core/json_exact.dart';
import '../wallet/wallet_core.dart';

class NodeInfo {
  const NodeInfo({
    required this.height,
    required this.targetHeight,
    required this.defaultFee,
    required this.minimumFee,
    required this.synchronized,
  });

  final int height;
  final int targetHeight;
  final Amount defaultFee;
  final Amount minimumFee;
  final bool synchronized;

  /// True when the node is online (daemon_network_state_online) or at least as high as the highest height it has seen.
  bool get isUsable => synchronized || (targetHeight > 0 && targetHeight <= height);
}

class AssetInfo {
  const AssetInfo({
    required this.assetId,
    required this.ticker,
    required this.fullName,
    required this.metaInfo,
    required this.decimalPoint,
    required this.totalMaxSupply,
    required this.currentSupply,
    required this.hiddenSupply,
    required this.owner,
  });

  final AssetId assetId;
  final String ticker;
  final String fullName;
  final String metaInfo;
  final int decimalPoint;
  final BigInt totalMaxSupply;
  final BigInt currentSupply;
  final bool hiddenSupply;
  final String owner;
}

class NodeException implements Exception {
  NodeException(this.message, {this.httpStatus, this.rpcCode});
  final String message;
  final int? httpStatus;
  final int? rpcCode;
  @override
  String toString() => 'NodeException($message${httpStatus == null ? '' : ', HTTP $httpStatus'})';
}

class NodeClient {
  NodeClient(this.endpoint, {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _http = client ?? http.Client();

  final NodeEndpoint endpoint;
  final Duration timeout;
  final http.Client _http;
  int _nextId = 0;

  void close() => _http.close();

  Uri _uri(String path) => endpoint.uri.replace(path: '${endpoint.uri.path.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, Object?>> _rpc(String method, [Map<String, Object?> params = const {}]) async {
    final body = encodeJsonExact({'jsonrpc': '2.0', 'id': _nextId++, 'method': method, 'params': params});
    final http.Response res;
    try {
      res = await _http
          .post(_uri('/json_rpc'), headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(timeout);
    } on Exception catch (e) {
      throw NodeException('node unreachable: $e');
    }
    if (res.statusCode == 429) {
      throw NodeException('node is rate limiting this client, try again shortly', httpStatus: 429);
    }
    if (res.statusCode == 403) {
      throw NodeException('node refused $method (not available on this node)', httpStatus: 403);
    }
    if (res.statusCode != 200) {
      throw NodeException('unexpected response from node', httpStatus: res.statusCode);
    }
    final Object? decoded;
    try {
      decoded = decodeJsonExact(res.body);
    } on JsonExactException catch (e) {
      throw NodeException('node sent invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) throw NodeException('node sent an unexpected reply');
    final err = decoded['error'];
    if (err is Map) {
      final code = err['code'];
      throw NodeException('$method failed: ${err['message']}', rpcCode: code is int ? code : null);
    }
    final result = decoded['result'];
    if (result is! Map<String, Object?>) throw NodeException('$method returned no result');
    return result;
  }

  /// daemon_network_state values from core_rpc_server_commands_defs.h
  static const int _stateOnline = 2;

  Future<NodeInfo> getInfo() async {
    final r = await _rpc('getinfo', {'flags': 0});
    _requireOk(r, 'getinfo');
    final height = _int(r['height']);
    final seen = _int(r['max_net_seen_height']);
    return NodeInfo(
      height: height,
      targetHeight: seen > height ? seen : height,
      defaultFee: Amount.fromAtomic(asBigInt(r['default_fee']) ?? defaultFee.atomic),
      minimumFee: Amount.fromAtomic(asBigInt(r['minimum_fee']) ?? defaultFee.atomic),
      synchronized: _int(r['daemon_network_state']) == _stateOnline,
    );
  }

  /// Returns null when the node reports the asset as not found.
  Future<AssetInfo?> getAssetInfo(AssetId id) async {
    final r = await _rpc('get_asset_info', {'asset_id': id.hex});
    if (r['status'] == _notFound) return null;
    _requireOk(r, 'get_asset_info');
    final d = r['asset_descriptor'];
    if (d is! Map<String, Object?>) return null;
    return _assetFrom(id, d);
  }

  /// Page of registered assets. [offset]/[count] map to get_assets_list.
  Future<List<AssetInfo>> listAssets({int offset = 0, int count = 50}) async {
    final r = await _rpc('get_assets_list', {'offset': offset, 'count': count});
    if (r['status'] == _notFound) return const [];
    _requireOk(r, 'get_assets_list');
    final list = r['assets'];
    if (list is! List) return const [];
    final out = <AssetInfo>[];
    for (final e in list) {
      if (e is Map<String, Object?>) {
        final id = e['asset_id'];
        if (id is String) out.add(_assetFrom(AssetId(id), e));
      }
    }
    return out;
  }

  AssetInfo _assetFrom(AssetId id, Map<String, Object?> d) => AssetInfo(
        assetId: id,
        ticker: (d['ticker'] as String?) ?? '',
        fullName: (d['full_name'] as String?) ?? '',
        metaInfo: (d['meta_info'] as String?) ?? '',
        decimalPoint: _int(d['decimal_point']),
        totalMaxSupply: asBigInt(d['total_max_supply']) ?? BigInt.zero,
        currentSupply: asBigInt(d['current_supply']) ?? BigInt.zero,
        hiddenSupply: d['hidden_supply'] == true,
        owner: (d['owner'] as String?) ?? '',
      );

  static const String _ok = 'OK';
  static const String _notFound = 'NOT_FOUND';

  /// Daemon replies carry a status string next to the payload; anything but OK is a failure.
  void _requireOk(Map<String, Object?> r, String method) {
    final status = r['status'];
    if (status != _ok) throw NodeException('$method failed: ${status ?? 'no status'}');
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    return 0;
  }
}
