import 'package:flutter/material.dart';

import '../app/wallet_controller.dart';
import '../node/node_client.dart';
import '../wallet/wallet_core.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final WalletController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _node = TextEditingController(text: widget.controller.node.url);
  String? _status;
  bool _statusIsError = false;
  bool _checking = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    NodeClient? client;
    try {
      final endpoint = NodeEndpoint(_node.text.trim());
      client = NodeClient(endpoint);
      final info = await client.getInfo();
      final warn = endpoint.isSecureEnough
          ? ''
          : '\nWarning: this is plain http over the network; use https.';
      setState(() {
        _statusIsError = false;
        _status =
            'Connected. Height ${info.height}${info.isUsable ? ', synchronized' : ', node is still syncing'}. '
            'Network fee ${info.defaultFee.format()} PDC.$warn';
      });
    } catch (e) {
      setState(() {
        _statusIsError = true;
        _status = describeError(e);
      });
    } finally {
      client?.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _apply() async {
    try {
      final endpoint = NodeEndpoint(_node.text.trim());
      await widget.controller.setNode(endpoint);
      if (mounted) {
        setState(() {
          _statusIsError = false;
          _status = 'Node changed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return PageList(
      children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _node,
          decoration: const InputDecoration(
            labelText: 'Node address',
            helperText:
                'The node sees which blocks and outputs your wallet asks for. Prefer your own node.',
          ),
        ),
        NodeAdvisory(field: _node, isDemoEngine: c.isDemoEngine),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: _checking ? null : _test,
              child: const Text('Test connection'),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: _apply, child: const Text('Use this node')),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(
            _status!,
            style: TextStyle(
              color: _statusIsError
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: c.lock,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Lock wallet'),
        ),
      ],
    );
  }
}
