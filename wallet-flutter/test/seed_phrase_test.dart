import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/core/seed_phrase.dart';

String words(int n) => List.generate(n, (i) => 'word${i + 1}').join(' ');

void main() {
  test('normalizing lower-cases and collapses line breaks, commas and odd spaces', () {
    expect(normalizeSeedPhrase('  Dew,  DEW\n\tdew;\u00a0dew  '), 'dew dew dew dew');
    expect(normalizeSeedPhrase('\u201cdew\u201d \u2018dew\u2019'), 'dew dew');
    expect(normalizeSeedPhrase(''), '');
    expect(normalizeSeedPhrase('  \n '), '');
  });

  test('digits and other characters are left alone so a real mistake stays visible', () {
    expect(normalizeSeedPhrase('1.dew 2.dew'), '1.dew 2.dew');
  });

  test('25 and 26 words are accepted', () {
    expect(checkSeedPhrase(words(25)), words(25));
    expect(checkSeedPhrase('${words(26)}\n'), words(26));
  });

  test('other counts are explained with the count that was entered', () {
    expect(() => checkSeedPhrase(''), throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('Enter your recovery phrase'))));
    for (final n in [1, 12, 27, 30]) {
      expect(() => checkSeedPhrase(words(n)), throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('25 or 26 words, but you entered $n'))));
    }
    expect(() => checkSeedPhrase(words(24)), throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('oldest format'))));
  });

  test('seedWordCount', () {
    expect(seedWordCount(''), 0);
    expect(seedWordCount('a b c'), 3);
  });
}
