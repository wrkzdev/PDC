import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../wallet/wallet_core.dart';

/// Shown at the top of every screen while the demo engine is active.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isDemoEngine) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Demo engine: balances are fake and nothing is sent to the network. Do not use real funds.',
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}

String describeError(Object e) {
  if (e is WalletException) return e.message;
  if (e is FormatException) return e.message;
  return e.toString();
}
