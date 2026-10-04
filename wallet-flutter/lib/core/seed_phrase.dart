// Client-side cleanup and checks for a recovery phrase, so a pasted phrase with stray formatting works and a phrase of
// the wrong length is explained before the engine (which only answers WRONG_SEED for every problem) is asked.
//
// The engine accepts exactly 25 words (24 + a date word, old format) or 26 words (24 + date + flags/checksum). A
// 24-word phrase of the oldest format is refused by the engine, and so is any other count.

const List<int> validSeedWordCounts = [25, 26];

/// Lower-cases (the word list is lower case), turns commas, semicolons, quotes and any line breaks or runs of spaces
/// into single spaces. Digits and other characters are left alone so a genuine mistake still shows up as one.
String normalizeSeedPhrase(String input) {
  final t = input
      .toLowerCase()
      .replaceAll(RegExp('[,;\u201c\u201d\u2018\u2019"\u00a0\u200b]'), ' ')
      .trim();
  if (t.isEmpty) return '';
  return t.split(RegExp(r'\s+')).join(' ');
}

int seedWordCount(String normalized) => normalized.isEmpty ? 0 : normalized.split(' ').length;

/// Returns the normalized phrase, or throws a FormatException saying what is wrong with its length.
String checkSeedPhrase(String input) {
  final phrase = normalizeSeedPhrase(input);
  final n = seedWordCount(phrase);
  if (n == 0) throw const FormatException('Enter your recovery phrase.');
  if (!validSeedWordCounts.contains(n)) {
    throw FormatException(
      'A recovery phrase has 25 or 26 words, but you entered $n. Check for missing or extra words'
      '${n == 24 ? ' (24-word phrases of the oldest format are not supported)' : ''}.',
    );
  }
  return phrase;
}
