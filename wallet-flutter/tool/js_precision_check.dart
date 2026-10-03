// Compiled to JavaScript and run under Node by tool/check_js_precision.sh: proves the amount and JSON code keeps
// uint64 values exact in a JS runtime, where a plain `jsonDecode` rounds anything above 2^53.
//
// Pure Dart (no Flutter imports) so `dart compile js` can build it.

import 'package:pdc_wallet/core/amount.dart';
import 'package:pdc_wallet/core/asset_rules.dart';
import 'package:pdc_wallet/core/json_exact.dart';

int _failures = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    // ignore: avoid_print
    print('ok   $name');
  } else {
    _failures++;
    // ignore: avoid_print
    print('FAIL $name: expected $expected, got $actual');
  }
}

void main() {
  final big = BigInt.parse('18446744073709551615'); // 2^64 - 1
  final justOver = BigInt.parse('9007199254740993'); // 2^53 + 1: a JS double cannot hold it

  final decoded = decodeJsonExact('{"total":18446744073709551615,"n":9007199254740993,"small":42}') as Map;
  check('decode 2^64-1', decoded['total'], big);
  check('decode 2^53+1', decoded['n'], justOver);
  check('decode small int', decoded['small'], 42);

  check('encode BigInt', encodeJsonExact({'a': big}), '{"a":18446744073709551615}');
  final roundTrip = decodeJsonExact(encodeJsonExact({'a': justOver})) as Map;
  check('round trip 2^53+1', roundTrip['a'], justOver);

  check('amount parse max', Amount.parse('18446744.073709551615').atomic, big);
  check('amount format max', Amount.fromAtomic(big).format(), '18446744.073709551615');
  check('amount add exact', (Amount.fromAtomic(justOver) + Amount.fromAtomic(BigInt.one)).atomic, justOver + BigInt.one);
  check('amount over uint64 rejected', _throws(() => Amount.fromAtomic(big + BigInt.one)), true);

  check('asset supply parse', AssetRules.parseSupply('1000000.000000000001', 12), BigInt.parse('1000000000000000001'));
  check('default fee', defaultFee.format(), '0.01');

  if (_failures != 0) {
    // ignore: avoid_print
    print('$_failures check(s) failed');
    throw StateError('JS precision check failed');
  }
  // ignore: avoid_print
  print('ALL OK');
}

bool _throws(void Function() f) {
  try {
    f();
    return false;
  } on RangeError {
    return true;
  }
}
