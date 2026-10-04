// Amounts in atomic units. PDC has 12 decimals; assets choose their own (0..18).
// Backed by BigInt because uint64 doesn't fit a JS number or a signed Dart int.

/// Number of decimals of the native coin (CURRENCY_DISPLAY_DECIMAL_POINT).
const int nativeDecimals = 12;

final BigInt maxUint64 = (BigInt.one << 64) - BigInt.one;

class Amount implements Comparable<Amount> {
  Amount.fromAtomic(this.atomic) {
    if (atomic.isNegative || atomic > maxUint64) {
      throw RangeError('amount out of uint64 range: $atomic');
    }
  }

  final BigInt atomic;

  static final Amount zero = Amount.fromAtomic(BigInt.zero);

  /// Parses a plain decimal string such as "1", "1.5" or "0.000000000001".
  /// No sign, exponent, separators or more fractional digits than [decimals].
  factory Amount.parse(String text, {int decimals = nativeDecimals}) {
    if (decimals < 0 || decimals > 18) {
      throw RangeError('decimals must be 0..18');
    }
    final t = text.trim();
    final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(t);
    if (m == null) throw FormatException('not a decimal amount', text);
    final whole = m.group(1)!;
    final frac = m.group(2) ?? '';
    if (frac.length > decimals) {
      throw FormatException('more than $decimals decimal places', text);
    }
    final digits = whole + frac.padRight(decimals, '0');
    return Amount.fromAtomic(BigInt.parse(digits));
  }

  /// Formats with exactly the needed decimals ("1.5"), or all of them when [trim] is false ("1.500000000000").
  String format({int decimals = nativeDecimals, bool trim = true}) {
    if (decimals < 0 || decimals > 18) {
      throw RangeError('decimals must be 0..18');
    }
    if (decimals == 0) return atomic.toString();
    final s = atomic.toString().padLeft(decimals + 1, '0');
    final whole = s.substring(0, s.length - decimals);
    var frac = s.substring(s.length - decimals);
    if (trim) {
      frac = frac.replaceFirst(RegExp(r'0+$'), '');
      if (frac.isEmpty) return whole;
    }
    return '$whole.$frac';
  }

  Amount operator +(Amount o) => Amount.fromAtomic(atomic + o.atomic);
  Amount operator -(Amount o) => Amount.fromAtomic(atomic - o.atomic);
  bool operator <(Amount o) => atomic < o.atomic;
  bool operator <=(Amount o) => atomic <= o.atomic;
  bool operator >(Amount o) => atomic > o.atomic;
  bool operator >=(Amount o) => atomic >= o.atomic;

  bool get isZero => atomic == BigInt.zero;

  @override
  int compareTo(Amount other) => atomic.compareTo(other.atomic);

  @override
  bool operator ==(Object other) => other is Amount && other.atomic == atomic;

  @override
  int get hashCode => atomic.hashCode;

  @override
  String toString() => 'Amount($atomic)';
}
