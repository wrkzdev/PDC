import 'package:flutter_test/flutter_test.dart';
import 'package:pdc_wallet/wallet/engine_errors.dart';

void main() {
  test('known engine codes become readable messages', () {
    expect(friendlyEngineError('WRONG_PASSWORD'), 'Wrong password.');
    expect(friendlyEngineError('WRONG_SEED'), contains('recovery phrase'));
    expect(friendlyEngineError('ALREADY_EXISTS'), contains('already'));
    expect(friendlyEngineError('WALLET_WRONG_ID'), contains('not open'));
    expect(friendlyEngineError('WALLET_RPC_ERROR_CODE_NOT_ENOUGH_MONEY'), contains('0.01 PDC'));
    expect(friendlyEngineError('-4'), contains('could not build the transaction'));
  });

  test('codes embedded in longer messages are recognised', () {
    expect(friendlyEngineError('WALLET_RPC_ERROR_CODE_GENERIC_TRANSFER_ERRORFailed to get asset info from daemon'),
        contains('does not know this asset'));
    expect(friendlyEngineError('x NOT_ENOUGH_MONEY y'), contains('Not enough funds'));
  });

  test('unknown messages are passed through untouched', () {
    expect(friendlyEngineError('  something new  '), 'something new');
    expect(friendlyEngineError(''), '');
  });
}
