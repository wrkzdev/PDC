import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/wallet_controller.dart';
import '../wallet/engine_choice.dart';
import '../wallet/engine_errors.dart';
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

String describeError(Object e) {
  if (e is WalletException) return friendlyEngineError(e.message);
  if (e is FormatException) return e.message;
  return e.toString();
}

/// Sync percentage that never rounds up to "100.0%" while the wallet is still behind: it is cut, not rounded, to 0.1%.
String formatSyncPercent(double progress) {
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  if (p >= 1) return '100';
  return ((p * 1000).floor() / 10).toStringAsFixed(1);
}

/// Copies [text] and confirms with a snackbar saying what was copied.
Future<void> copyText(
  BuildContext context,
  String text, {
  String what = 'Copied',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(what), duration: const Duration(seconds: 2)),
      );
  }
}

class CopyIconButton extends StatelessWidget {
  const CopyIconButton({
    super.key,
    required this.text,
    required this.what,
    this.tooltip,
  });

  final String text;

  /// Shown in the confirmation, e.g. "Address copied".
  final String what;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.copy_outlined),
    tooltip: tooltip ?? 'Copy',
    visualDensity: VisualDensity.compact,
    onPressed: () => copyText(context, text, what: what),
  );
}

/// The PDC mark on its dark tile, so it reads on light and dark themes alike.
class PdcMark extends StatelessWidget {
  const PdcMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E2A),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/brand/pdc-mark.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.lock_outline,
          size: size * 0.55,
          color: const Color(0xFF3BC7FF),
        ),
      ),
    );
  }
}

/// A scrolling page that stays a readable width on big windows instead of stretching edge to edge.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.maxWidth = 760});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: children,
        ),
      ),
    );
  }
}

/// What to tell the user about the connection to [node], or null when there is nothing to warn about. Both http:// and
/// https:// are accepted for remote nodes (the user's choice); this only makes the trade-off visible.
String? nodeAdvisory(NodeEndpoint node, {required bool isDemoEngine}) {
  final h = node.uri.host;
  final loopback = h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  if (loopback) return null;
  if (node.uri.scheme == 'http') {
    return 'Plain http: this connection is not encrypted, so anyone on the path can see what your wallet asks the node '
        'for and can alter its answers. Keys never leave this device, but use a node and network you trust.';
  }
  if (!isDemoEngine && !engineSupportsTls) {
    return 'Note: this build of the wallet engine does not encrypt the node connection yet, even for https:// addresses. '
        'Use a node and network you trust, or reach the node through a local TLS proxy.';
  }
  return null;
}

/// Shows [nodeAdvisory] for whatever is typed in [field], live.
class NodeAdvisory extends StatelessWidget {
  const NodeAdvisory({super.key, required this.field, required this.isDemoEngine});

  final TextEditingController field;
  final bool isDemoEngine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: field,
      builder: (context, _) {
        String? text;
        try {
          text = nodeAdvisory(NodeEndpoint(field.text.trim()), isDemoEngine: isDemoEngine);
        } on FormatException {
          text = null;
        }
        if (text == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
