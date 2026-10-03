// Turns the codes the wallet engine answers with into text a person can act on. The codes are what the real engine
// returned in tests/real-engine runs (utils/docker walletlib-dart-check); unknown ones are shown as they are.

String friendlyEngineError(String raw) {
  final r = raw.trim();
  const exact = <String, String>{
    'WRONG_PASSWORD': 'Wrong password.',
    'WRONG_SEED': 'That recovery phrase is not valid. Check every word and their order.',
    'ALREADY_EXISTS': 'A wallet with that name already exists or is already open.',
    'WALLET_WRONG_ID': 'The wallet is not open. Unlock it again.',
    'FILE_NOT_FOUND': 'No wallet with that name was found.',
    'WALLET_RPC_ERROR_CODE_NOT_ENOUGH_MONEY':
        'Not enough funds. Remember the 0.01 PDC network fee, and that received coins stay locked for a few blocks.',
    'BUSY': 'The wallet is busy synchronizing. Try again in a moment.',
  };
  final hit = exact[r];
  if (hit != null) return hit;
  if (r.contains('Failed to get asset info from daemon')) {
    return 'The node does not know this asset, or could not be reached.';
  }
  if (r.contains('NOT_ENOUGH_MONEY')) return exact['WALLET_RPC_ERROR_CODE_NOT_ENOUGH_MONEY']!;
  if (r.contains('WRONG_PASSWORD')) return exact['WRONG_PASSWORD']!;
  return r;
}
