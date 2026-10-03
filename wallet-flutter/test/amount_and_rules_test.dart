import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/core/amount.dart';
import 'package:pdc_wallet/core/asset_rules.dart';

AssetDraft draft({
  String ticker = 'GOLD',
  String fullName = 'Gold Token',
  int decimals = 12,
  String max = '1000',
  String initial = '10',
}) =>
    AssetDraft(
      ticker: ticker,
      fullName: fullName,
      decimalPoint: decimals,
      totalMaxSupply: AssetRules.parseSupply(max, decimals.clamp(0, 18)),
      initialSupply: AssetRules.parseSupply(initial, decimals.clamp(0, 18)),
    );

void main() {
  group('Amount', () {
    test('parses and formats the native coin (12 decimals)', () {
      expect(Amount.parse('1').atomic, BigInt.parse('1000000000000'));
      expect(Amount.parse('0.01').atomic, BigInt.from(10000000000));
      expect(Amount.parse('0.000000000001').atomic, BigInt.one);
      expect(Amount.parse('1.5').format(), '1.5');
      expect(Amount.parse('2').format(), '2');
      expect(Amount.parse('2').format(trim: false), '2.000000000000');
      expect(Amount.fromAtomic(BigInt.one).format(), '0.000000000001');
      expect(Amount.zero.format(), '0');
    });

    test('is exact up to the uint64 maximum', () {
      final max = Amount.fromAtomic(maxUint64);
      expect(max.format(), '18446744.073709551615');
      expect(Amount.parse(max.format()), max);
      expect(() => Amount.fromAtomic(maxUint64 + BigInt.one), throwsRangeError);
      expect(() => Amount.fromAtomic(BigInt.from(-1)), throwsRangeError);
      expect(() => max + Amount.fromAtomic(BigInt.one), throwsRangeError);
    });

    test('rejects anything that is not a plain decimal', () {
      for (final bad in ['', ' ', '-1', '+1', '1e3', '1,5', '.5', '5.', '1.2.3', 'abc', '1 000', '0.0000000000001']) {
        expect(() => Amount.parse(bad), throwsFormatException, reason: 'input: "$bad"');
      }
    });

    test('supports other decimal places', () {
      expect(Amount.parse('1.25', decimals: 2).atomic, BigInt.from(125));
      expect(Amount.parse('7', decimals: 0).atomic, BigInt.from(7));
      expect(Amount.fromAtomic(BigInt.from(125)).format(decimals: 2), '1.25');
      expect(Amount.fromAtomic(BigInt.from(7)).format(decimals: 0), '7');
      expect(() => Amount.parse('1.5', decimals: 0), throwsFormatException);
      expect(() => Amount.parse('1', decimals: 19), throwsRangeError);
    });

    test('compares', () {
      expect(Amount.parse('1') < Amount.parse('2'), isTrue);
      expect(Amount.parse('2') >= Amount.parse('2'), isTrue);
      expect(Amount.parse('1'), Amount.fromAtomic(BigInt.parse('1000000000000')));
    });
  });

  group('AssetRules', () {
    test('accepts a normal asset', () {
      expect(AssetRules.validate(draft()), isEmpty);
    });

    test('ticker: 1-14 letters or digits', () {
      for (final bad in ['', 'GOLD COIN', 'GO-LD', 'ABCDEFGHIJKLMNO', 'GÖLD', 'GOLD\n']) {
        expect(AssetRules.validate(draft(ticker: bad)), isNotEmpty, reason: 'ticker "$bad"');
      }
      for (final good in ['G', 'gold', 'GOLD123', 'ABCDEFGHIJKLMN']) {
        expect(AssetRules.validate(draft(ticker: good)), isEmpty, reason: 'ticker "$good"');
      }
    });

    test('full name: restricted character set, up to 400', () {
      expect(AssetRules.validate(draft(fullName: '')), isEmpty);
      expect(AssetRules.validate(draft(fullName: 'Gold, (v2): wow! ok?')), isEmpty);
      expect(AssetRules.validate(draft(fullName: 'A' * 400)), isEmpty);
      expect(AssetRules.validate(draft(fullName: 'A' * 401)), isNotEmpty);
      for (final bad in ['Gold_Token', 'Gold/Token', 'Gold\nToken', 'Goldé']) {
        expect(AssetRules.validate(draft(fullName: bad)), isNotEmpty, reason: 'name "$bad"');
      }
    });

    test('decimals 0..18', () {
      expect(AssetRules.validate(draft(decimals: 0, max: '1000', initial: '10')), isEmpty);
      expect(AssetRules.validate(draft(decimals: 18, max: '1', initial: '1')), isEmpty);
      final tooMany = AssetDraft(
          ticker: 'GOLD', fullName: 'x', decimalPoint: 19, totalMaxSupply: BigInt.one, initialSupply: BigInt.zero);
      expect(AssetRules.validate(tooMany), isNotEmpty);
    });

    test('supply limits', () {
      expect(AssetRules.validate(draft(max: '10', initial: '10')), isEmpty);
      expect(AssetRules.validate(draft(max: '10', initial: '11')), isNotEmpty);
      expect(AssetRules.validate(draft(max: '0', initial: '0')), isNotEmpty);
            final atMax = AssetDraft(ticker: 'BIG', fullName: '', decimalPoint: 12, totalMaxSupply: maxUint64, initialSupply: maxUint64);
      expect(AssetRules.validate(atMax), isEmpty);
      final over = AssetDraft(ticker: 'BIG', fullName: '', decimalPoint: 12, totalMaxSupply: maxUint64 + BigInt.one, initialSupply: BigInt.zero);
      expect(AssetRules.validate(over), isNotEmpty);
    });

    test('default fee is 0.01 PDC', () {
      expect(defaultFee.format(), '0.01');
    });
  });
}
