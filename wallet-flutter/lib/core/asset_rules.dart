// Client-side checks for deploying an asset. They mirror what the node and wallet2 enforce
// (src/currency_core/currency_format_utils.cpp ASSET_TICKER_REGEXP / ASSET_FULL_NAME_REGEXP, wallet2::deploy_new_asset)
// so the user gets a clear message before the wallet builds a transaction. The node stays the authority.

import 'amount.dart';

/// 0.01 PDC: TX_DEFAULT_FEE == TX_MINIMUM_FEE in currency_config.h. Asset operations pay only this fee.
final Amount defaultFee = Amount.fromAtomic(BigInt.from(10000000000));

class AssetDraft {
  const AssetDraft({
    required this.ticker,
    required this.fullName,
    required this.decimalPoint,
    required this.totalMaxSupply,
    required this.initialSupply,
    this.metaInfo = '',
    this.hiddenSupply = false,
  });

  final String ticker;
  final String fullName;
  final String metaInfo;
  final int decimalPoint;

  /// Atomic units (value * 10^decimalPoint).
  final BigInt totalMaxSupply;

  /// Atomic units emitted to the deployer's address in the registering transaction.
  final BigInt initialSupply;
  final bool hiddenSupply;
}

class AssetRules {
  AssetRules._();

  static final RegExp _ticker = RegExp(r'^[A-Za-z0-9]{1,14}$');
  static final RegExp _fullName = RegExp(r'^[A-Za-z0-9.,:!?\-() ]{0,400}$');

  static const int maxDecimalPoint = 18;

  /// Returns a list of human-readable problems; empty means the draft is acceptable.
  static List<String> validate(AssetDraft d) {
    final problems = <String>[];
    if (!_ticker.hasMatch(d.ticker)) {
      problems.add('Ticker must be 1-14 letters or digits.');
    }
    if (!_fullName.hasMatch(d.fullName)) {
      problems.add(
        'Name may use letters, digits, spaces and . , : ! ? - ( ) only (up to 400 characters).',
      );
    }
    if (d.decimalPoint < 0 || d.decimalPoint > maxDecimalPoint) {
      problems.add('Decimal places must be between 0 and $maxDecimalPoint.');
    }
    if (d.totalMaxSupply <= BigInt.zero || d.totalMaxSupply > maxUint64) {
      problems.add(
        'Maximum supply must be greater than zero and fit in 64 bits.',
      );
    }
    if (d.initialSupply.isNegative || d.initialSupply > maxUint64) {
      problems.add('Initial supply must be zero or more and fit in 64 bits.');
    } else if (d.initialSupply > d.totalMaxSupply) {
      problems.add('Initial supply cannot exceed the maximum supply.');
    }
    return problems;
  }

  /// Parses a decimal supply string for an asset with [decimalPoint] places into atomic units.
  static BigInt parseSupply(String text, int decimalPoint) =>
      Amount.parse(text, decimals: decimalPoint).atomic;
}
