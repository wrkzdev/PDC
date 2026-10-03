import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/core/json_exact.dart';

void main() {
  group('decodeJsonExact', () {
    test('keeps uint64 values above 2^53 exactly', () {
      final m = decodeJsonExact('{"total":18446744073709551615,"unlocked":9007199254740993}') as Map;
      expect(m['total'], BigInt.parse('18446744073709551615'));
      expect(m['unlocked'], BigInt.parse('9007199254740993')); // 2^53 + 1, a double would round this
    });

    test('small integers stay int, others double', () {
      final m = decodeJsonExact('{"a":42,"b":-7,"c":9007199254740991,"d":1.5,"e":1e3,"f":0}') as Map;
      expect(m['a'], 42);
      expect(m['b'], -7);
      expect(m['c'], 9007199254740991);
      expect(m['d'], 1.5);
      expect(m['e'], 1000.0);
      expect(m['f'], 0);
    });

    test('parses nested structures, literals and escapes', () {
      final v = decodeJsonExact(' {"a":[1,2,{"b":null}],"s":"x\\"y\\\\z\\n\\u0041","t":true,"f":false} ') as Map;
      expect(v['a'], [1, 2, {'b': null}]);
      expect(v['s'], 'x"y\\z\nA');
      expect(v['t'], true);
      expect(v['f'], false);
    });

    test('rejects malformed input', () {
      for (final bad in ['', '{', '{"a":}', '[1,]', '{"a":1,}', '01', '1.', '"abc', 'nul', '{"a":1} x', '{a:1}', '"\u0001"', '-', '1e']) {
        expect(() => decodeJsonExact(bad), throwsA(isA<JsonExactException>()), reason: 'input: $bad');
      }
    });

    test('limits nesting depth', () {
      expect(() => decodeJsonExact('${'[' * 100}${']' * 100}'), throwsA(isA<JsonExactException>()));
    });
  });

  group('encodeJsonExact', () {
    test('writes BigInt as an unquoted integer', () {
      expect(encodeJsonExact({'a': BigInt.parse('18446744073709551615')}), '{"a":18446744073709551615}');
    });

    test('round-trips what it writes', () {
      final original = {
        'amount': BigInt.parse('9007199254740993'),
        'list': [1, 'two', null, true, 2.5],
        'nested': {'k': 'v "quoted"'},
      };
      final back = decodeJsonExact(encodeJsonExact(original)) as Map;
      expect(back['amount'], original['amount']);
      expect(back['list'], original['list']);
      expect(back['nested'], original['nested']);
    });

    test('refuses things JSON cannot hold', () {
      expect(() => encodeJsonExact(double.nan), throwsArgumentError);
      expect(() => encodeJsonExact({1: 2}), throwsArgumentError);
      expect(() => encodeJsonExact(Object()), throwsArgumentError);
    });
  });

  test('asBigInt accepts int, BigInt and decimal strings only', () {
    expect(asBigInt(5), BigInt.from(5));
    expect(asBigInt(BigInt.two), BigInt.two);
    expect(asBigInt('123'), BigInt.from(123));
    expect(asBigInt('x'), isNull);
    expect(asBigInt(1.5), isNull);
    expect(asBigInt(null), isNull);
  });
}
