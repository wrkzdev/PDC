// JSON codec that never loses integer precision.
//
// PDC amounts and asset supplies are uint64 atomic units. dart:convert decodes every JSON number to a double on
// the web (53 bits of precision) and to a signed 64-bit int on the VM, so a balance above 2^53 (about 9007 PDC) or
// a supply near 2^64 would be silently rounded or wrap. Here integers that don't fit 2^53 come back as BigInt on
// every platform, and BigInt values are written out as plain digits.

import 'dart:convert';

class JsonExactException implements Exception {
  JsonExactException(this.message, this.offset);
  final String message;
  final int offset;
  @override
  String toString() => 'JsonExactException: $message at offset $offset';
}

final BigInt _maxSafeInt = BigInt.from(9007199254740991); // 2^53 - 1
const int _maxDepth = 64;

/// Decodes JSON. Objects become `Map<String, Object?>`, arrays `List<Object?>`, integers `int` (when |n| < 2^53) or
/// `BigInt`, other numbers `double`.
Object? decodeJsonExact(String text) {
  final p = _Parser(text);
  final v = p.parseValue(0);
  p.skipWs();
  if (p.pos != text.length) {
    throw JsonExactException('unexpected trailing characters', p.pos);
  }
  return v;
}

/// Encodes JSON; BigInt is written as an unquoted integer.
String encodeJsonExact(Object? value) {
  final sb = StringBuffer();
  _encode(value, sb, 0);
  return sb.toString();
}

void _encode(Object? v, StringBuffer sb, int depth) {
  if (depth > _maxDepth) throw ArgumentError('JSON nested too deeply');
  if (v == null) {
    sb.write('null');
  } else if (v is bool) {
    sb.write(v ? 'true' : 'false');
  } else if (v is BigInt) {
    sb.write(v.toString());
  } else if (v is int) {
    sb.write(v.toString());
  } else if (v is double) {
    if (v.isNaN || v.isInfinite) {
      throw ArgumentError('NaN/Infinity is not JSON');
    }
    sb.write(v.toString());
  } else if (v is String) {
    sb.write(jsonEncode(v));
  } else if (v is Map) {
    sb.write('{');
    var first = true;
    v.forEach((k, val) {
      if (k is! String) throw ArgumentError('JSON object keys must be strings');
      if (!first) sb.write(',');
      first = false;
      sb.write(jsonEncode(k));
      sb.write(':');
      _encode(val, sb, depth + 1);
    });
    sb.write('}');
  } else if (v is Iterable) {
    sb.write('[');
    var first = true;
    for (final e in v) {
      if (!first) sb.write(',');
      first = false;
      _encode(e, sb, depth + 1);
    }
    sb.write(']');
  } else {
    throw ArgumentError('Cannot encode ${v.runtimeType} as JSON');
  }
}

/// Reads an unsigned integer field that may arrive as int, BigInt or a decimal string.
BigInt? asBigInt(Object? v) {
  if (v == null) return null;
  if (v is BigInt) return v;
  if (v is int) return BigInt.from(v);
  if (v is String) return BigInt.tryParse(v);
  return null;
}

class _Parser {
  _Parser(this.s);
  final String s;
  int pos = 0;

  void skipWs() {
    while (pos < s.length) {
      final c = s.codeUnitAt(pos);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        pos++;
      } else {
        break;
      }
    }
  }

  Never fail(String m) => throw JsonExactException(m, pos);

  Object? parseValue(int depth) {
    if (depth > _maxDepth) fail('nested too deeply');
    skipWs();
    if (pos >= s.length) fail('unexpected end of input');
    final c = s[pos];
    switch (c) {
      case '{':
        return _parseObject(depth);
      case '[':
        return _parseArray(depth);
      case '"':
        return _parseString();
      case 't':
        return _literal('true', true);
      case 'f':
        return _literal('false', false);
      case 'n':
        return _literal('null', null);
      default:
        return _parseNumber();
    }
  }

  Object? _literal(String word, Object? value) {
    if (!s.startsWith(word, pos)) fail('invalid literal');
    pos += word.length;
    return value;
  }

  Map<String, Object?> _parseObject(int depth) {
    pos++; // {
    final m = <String, Object?>{};
    skipWs();
    if (pos < s.length && s[pos] == '}') {
      pos++;
      return m;
    }
    while (true) {
      skipWs();
      if (pos >= s.length || s[pos] != '"') fail('object key must be a string');
      final key = _parseString();
      skipWs();
      if (pos >= s.length || s[pos] != ':') fail("expected ':'");
      pos++;
      m[key] = parseValue(depth + 1);
      skipWs();
      if (pos >= s.length) fail('unterminated object');
      if (s[pos] == ',') {
        pos++;
        continue;
      }
      if (s[pos] == '}') {
        pos++;
        return m;
      }
      fail("expected ',' or '}'");
    }
  }

  List<Object?> _parseArray(int depth) {
    pos++; // [
    final l = <Object?>[];
    skipWs();
    if (pos < s.length && s[pos] == ']') {
      pos++;
      return l;
    }
    while (true) {
      l.add(parseValue(depth + 1));
      skipWs();
      if (pos >= s.length) fail('unterminated array');
      if (s[pos] == ',') {
        pos++;
        continue;
      }
      if (s[pos] == ']') {
        pos++;
        return l;
      }
      fail("expected ',' or ']'");
    }
  }

  String _parseString() {
    pos++; // opening quote
    final sb = StringBuffer();
    while (true) {
      if (pos >= s.length) fail('unterminated string');
      final c = s.codeUnitAt(pos);
      if (c == 0x22) {
        pos++;
        return sb.toString();
      }
      if (c < 0x20) fail('control character in string');
      if (c == 0x5c) {
        pos++;
        if (pos >= s.length) fail('unterminated escape');
        final e = s[pos];
        switch (e) {
          case '"':
            sb.write('"');
          case '\\':
            sb.write('\\');
          case '/':
            sb.write('/');
          case 'b':
            sb.write('\b');
          case 'f':
            sb.write('\f');
          case 'n':
            sb.write('\n');
          case 'r':
            sb.write('\r');
          case 't':
            sb.write('\t');
          case 'u':
            if (pos + 4 >= s.length) fail('bad \\u escape');
            final hex = s.substring(pos + 1, pos + 5);
            final code = int.tryParse(hex, radix: 16);
            if (code == null) fail('bad \\u escape');
            sb.writeCharCode(code);
            pos += 4;
          default:
            fail('bad escape');
        }
        pos++;
      } else {
        sb.writeCharCode(c);
        pos++;
      }
    }
  }

  Object _parseNumber() {
    final start = pos;
    if (pos < s.length && s[pos] == '-') pos++;
    final digitsStart = pos;
    while (pos < s.length && _isDigit(s.codeUnitAt(pos))) {
      pos++;
    }
    if (pos == digitsStart) fail('invalid number');
    if (s.codeUnitAt(digitsStart) == 0x30 && pos - digitsStart > 1) {
      fail('leading zero');
    }
    var isInt = true;
    if (pos < s.length && s[pos] == '.') {
      isInt = false;
      pos++;
      final f = pos;
      while (pos < s.length && _isDigit(s.codeUnitAt(pos))) {
        pos++;
      }
      if (pos == f) fail('invalid fraction');
    }
    if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
      isInt = false;
      pos++;
      if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++;
      final e = pos;
      while (pos < s.length && _isDigit(s.codeUnitAt(pos))) {
        pos++;
      }
      if (pos == e) fail('invalid exponent');
    }
    final text = s.substring(start, pos);
    if (!isInt) return double.parse(text);
    final big = BigInt.parse(text);
    if (big.abs() <= _maxSafeInt) return big.toInt();
    return big;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}
