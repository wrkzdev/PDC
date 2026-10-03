import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdc_wallet/core/json_exact.dart';
import 'package:pdc_wallet/node/node_client.dart';
import 'package:pdc_wallet/wallet/wallet_core.dart';

NodeClient clientFor(Future<http.Response> Function(http.Request) handler, {String url = 'https://node.example.org'}) =>
    NodeClient(NodeEndpoint(url), client: MockClient(handler));

http.Response ok(String body) => http.Response(body, 200, headers: {'content-type': 'application/json'});

String rpcResult(String resultJson) => '{"id":0,"jsonrpc":"2.0","result":$resultJson}';

void main() {
  group('NodeEndpoint', () {
    test('requires an http(s) URL with a host', () {
      for (final bad in ['', 'node.example.org', 'ftp://node.example.org', 'https://', 'not a url']) {
        expect(() => NodeEndpoint(bad), throwsFormatException, reason: bad);
      }
      expect(NodeEndpoint('https://node.example.org:19211').uri.port, 19211);
    });

    test('plain http is only secure enough on loopback', () {
      expect(NodeEndpoint('https://node.example.org').isSecureEnough, isTrue);
      expect(NodeEndpoint('http://127.0.0.1:19211').isSecureEnough, isTrue);
      expect(NodeEndpoint('http://localhost:19211').isSecureEnough, isTrue);
      expect(NodeEndpoint('http://[::1]:19211').isSecureEnough, isTrue);
      expect(NodeEndpoint('http://node.example.org').isSecureEnough, isFalse);
      expect(NodeEndpoint('http://192.168.1.5:19211').isSecureEnough, isFalse);
    });
  });

  group('getInfo', () {
    test('posts a json_rpc request and reads the daemon reply', () async {
      late http.Request seen;
      final c = clientFor((req) async {
        seen = req;
        return ok(rpcResult(
            '{"status":"OK","height":1986,"max_net_seen_height":1986,"daemon_network_state":2,"default_fee":10000000000,"minimum_fee":10000000000}'));
      });
      final info = await c.getInfo();
      expect(seen.url.toString(), 'https://node.example.org/json_rpc');
      expect(seen.method, 'POST');
      final sent = decodeJsonExact(seen.body) as Map;
      expect(sent['method'], 'getinfo');
      expect(sent['jsonrpc'], '2.0');
      expect(info.height, 1986);
      expect(info.synchronized, isTrue);
      expect(info.isUsable, isTrue);
      expect(info.defaultFee.format(), '0.01');
    });

    test('a node that is still synchronizing is not usable', () async {
      final c = clientFor((_) async => ok(rpcResult(
          '{"status":"OK","height":500,"max_net_seen_height":1986,"daemon_network_state":1,"default_fee":10000000000,"minimum_fee":10000000000}')));
      final info = await c.getInfo();
      expect(info.synchronized, isFalse);
      expect(info.targetHeight, 1986);
      expect(info.isUsable, isFalse);
    });

    test('keeps the base path when the node sits behind a prefix', () async {
      late Uri seen;
      final c = clientFor((req) async {
        seen = req.url;
        return ok(rpcResult('{"status":"OK","height":1,"daemon_network_state":2}'));
      }, url: 'https://example.org/pdc/');
      await c.getInfo();
      expect(seen.path, '/pdc/json_rpc');
    });

    test('a non-OK daemon status is an error', () async {
      final c = clientFor((_) async => ok(rpcResult('{"status":"BUSY","height":1}')));
      expect(c.getInfo(), throwsA(isA<NodeException>()));
    });
  });

  group('errors', () {
    test('429 and 403 get specific messages', () async {
      final limited = clientFor((_) async => http.Response('', 429));
      await expectLater(limited.getInfo(), throwsA(isA<NodeException>().having((e) => e.httpStatus, 'status', 429)));
      final refused = clientFor((_) async => http.Response('{"error":"nope"}', 403));
      await expectLater(refused.getInfo(), throwsA(isA<NodeException>().having((e) => e.httpStatus, 'status', 403)));
    });

    test('unreachable node, bad JSON and JSON-RPC errors become NodeException', () async {
      final down = clientFor((_) async => throw http.ClientException('connection refused'));
      await expectLater(down.getInfo(), throwsA(isA<NodeException>()));
      final junk = clientFor((_) async => ok('<html>'));
      await expectLater(junk.getInfo(), throwsA(isA<NodeException>()));
      final rpcErr = clientFor((_) async => ok('{"id":0,"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}'));
      await expectLater(rpcErr.getInfo(), throwsA(isA<NodeException>().having((e) => e.rpcCode, 'code', -32601)));
    });

    test('times out instead of hanging', () async {
      final c = NodeClient(
        NodeEndpoint('https://node.example.org'),
        client: MockClient((_) => Future<http.Response>.delayed(const Duration(seconds: 5), () => ok('{}'))),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(c.getInfo(), throwsA(isA<NodeException>()));
    });
  });

  group('assets', () {
    const id = 'a5000000000000000000000000000000000000000000000000000000000000ff';

    test('getAssetInfo reads supplies without losing precision', () async {
      late Map sent;
      final c = clientFor((req) async {
        sent = decodeJsonExact(req.body) as Map;
        return ok(rpcResult('{"status":"OK","asset_descriptor":{"ticker":"GOLD","full_name":"Gold","meta_info":"m",'
            '"decimal_point":12,"total_max_supply":18446744073709551615,"current_supply":9007199254740993,'
            '"hidden_supply":false,"owner":"abcd"}}'));
      });
      final a = await c.getAssetInfo(const AssetId(id));
      expect(sent['method'], 'get_asset_info');
      expect((sent['params'] as Map)['asset_id'], id);
      expect(a, isNotNull);
      expect(a!.ticker, 'GOLD');
      expect(a.totalMaxSupply, BigInt.parse('18446744073709551615'));
      expect(a.currentSupply, BigInt.parse('9007199254740993'));
    });

    test('unknown asset is null, not an exception', () async {
      final c = clientFor((_) async => ok(rpcResult('{"status":"NOT_FOUND"}')));
      expect(await c.getAssetInfo(const AssetId(id)), isNull);
    });

    test('listAssets maps the list and passes the page', () async {
      late Map params;
      final c = clientFor((req) async {
        params = (decodeJsonExact(req.body) as Map)['params'] as Map;
        return ok(rpcResult('{"status":"OK","assets":['
            '{"asset_id":"$id","ticker":"A","full_name":"Alpha","decimal_point":2,"total_max_supply":100,"current_supply":50},'
            '{"asset_id":"b5","ticker":"B","full_name":"Beta","decimal_point":0,"total_max_supply":7,"current_supply":7}]}'));
      });
      final list = await c.listAssets(offset: 10, count: 2);
      expect(params['offset'], 10);
      expect(params['count'], 2);
      expect(list.map((a) => a.ticker), ['A', 'B']);
      expect(list.first.assetId.hex, id);
    });

    test('request body is valid JSON the gateway allowlist accepts (one method key, no backslashes)', () async {
      late String body;
      final c = clientFor((req) async {
        body = utf8.decode(req.bodyBytes);
        return ok(rpcResult('{"status":"NOT_FOUND"}'));
      });
      await c.getAssetInfo(const AssetId(id));
      expect('"method"'.allMatches(body).length, 1);
      expect(body.contains(r'\'), isFalse);
    });
  });
}
